#define _GNU_SOURCE
#include <dlfcn.h>
#include <time.h>
#include <sys/time.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>

/* Real libc symbols */
static int    (*real_clock_gettime)(clockid_t, struct timespec *) = NULL;
static int    (*real_gettimeofday)(struct timeval *, void *) = NULL;
static time_t (*real_time)(time_t *) = NULL;

/* Configuration file path */
static const char *CONFIG_FILE = "/tmp/pg_mock_time.conf";

/* Configuration structure */
typedef struct {
    bool enabled;
    bool use_offset;
    long long fixed_sec;
    long fixed_nsec;
    long long off_sec;
    long off_nsec;
} MockConfig;

/* Read configuration from file */
static bool read_config(MockConfig *cfg) {
    FILE *f = fopen(CONFIG_FILE, "r");
    if (!f) return false;
    
    int n = fscanf(f, "%d %d %lld %ld %lld %ld",
                   &cfg->enabled, &cfg->use_offset,
                   &cfg->fixed_sec, &cfg->fixed_nsec,
                   &cfg->off_sec, &cfg->off_nsec);
    fclose(f);
    return n == 6;
}

/* Resolve real symbols on first use */
static void ensure_real(void) {
    if (!real_clock_gettime) {
        real_clock_gettime = dlsym(RTLD_NEXT, "clock_gettime");
    }
    if (!real_gettimeofday) {
        real_gettimeofday = dlsym(RTLD_NEXT, "gettimeofday");
    }
    if (!real_time) {
        real_time = dlsym(RTLD_NEXT, "time");
    }
}

/* Normalize timespec */
static inline void norm_ts(struct timespec *ts) {
    while (ts->tv_nsec >= 1000000000L) { 
        ts->tv_sec += 1; 
        ts->tv_nsec -= 1000000000L; 
    }
    while (ts->tv_nsec < 0) { 
        ts->tv_sec -= 1; 
        ts->tv_nsec += 1000000000L; 
    }
}

/* Interpose clock_gettime */
int clock_gettime(clockid_t clk_id, struct timespec *tp) {
    MockConfig cfg = {0};
    ensure_real();
    
    int rc = real_clock_gettime(clk_id, tp);
    if (rc != 0) return rc;
    
    if (!read_config(&cfg) || !cfg.enabled)
        return 0;
    
    /* Only fake wall clock time */
    if (clk_id == CLOCK_REALTIME
#ifdef CLOCK_REALTIME_COARSE
        || clk_id == CLOCK_REALTIME_COARSE
#endif
       ) {
        if (cfg.use_offset) {
            tp->tv_sec  += cfg.off_sec;
            tp->tv_nsec += cfg.off_nsec;
            norm_ts(tp);
        } else {
            tp->tv_sec  = cfg.fixed_sec;
            tp->tv_nsec = cfg.fixed_nsec;
        }
    }
    return 0;
}

/* Interpose gettimeofday */
int gettimeofday(struct timeval *tv, void *tz) {
    MockConfig cfg = {0};
    ensure_real();
    
    int rc = real_gettimeofday(tv, tz);
    if (rc != 0) return rc;
    
    if (!read_config(&cfg) || !cfg.enabled)
        return 0;
    
    if (cfg.use_offset) {
        long usec = tv->tv_usec + (cfg.off_nsec / 1000);
        tv->tv_sec += cfg.off_sec;
        while (usec >= 1000000L) { 
            tv->tv_sec += 1; 
            usec -= 1000000L; 
        }
        while (usec < 0) { 
            tv->tv_sec -= 1; 
            usec += 1000000L; 
        }
        tv->tv_usec = usec;
    } else {
        tv->tv_sec  = cfg.fixed_sec;
        tv->tv_usec = cfg.fixed_nsec / 1000;
    }
    return 0;
}

/* Interpose time() */
time_t time(time_t *tloc) {
    MockConfig cfg = {0};
    ensure_real();
    
    time_t real = real_time(NULL);
    
    if (!read_config(&cfg) || !cfg.enabled) {
        if (tloc) *tloc = real;
        return real;
    }
    
    time_t out;
    if (cfg.use_offset) {
        out = real + cfg.off_sec + (cfg.off_nsec >= 0 ? 0 : -1);
    } else {
        out = cfg.fixed_sec;
    }
    
    if (tloc) *tloc = out;
    return out;
}