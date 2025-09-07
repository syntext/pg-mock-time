#include <stdio.h>
#include <math.h>
#include <string.h>
#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"

PG_MODULE_MAGIC;

/* Configuration file path */
static const char *CONFIG_FILE = "/tmp/pg_mock_time.conf";

/* SQL function declarations */
PG_FUNCTION_INFO_V1(set_mock_time_epoch);
PG_FUNCTION_INFO_V1(set_mock_time_offset_seconds);
PG_FUNCTION_INFO_V1(clear_mock_time);
PG_FUNCTION_INFO_V1(pg_mock_time_status);

/* Write configuration to file */
static void write_config(bool enabled, bool use_offset, 
                         long long fixed_sec, long fixed_nsec,
                         long long off_sec, long off_nsec) {
    FILE *f = fopen(CONFIG_FILE, "w");
    if (f) {
        fprintf(f, "%d %d %lld %ld %lld %ld\n",
                enabled, use_offset, fixed_sec, fixed_nsec, off_sec, off_nsec);
        fclose(f);
    }
}

/* Set absolute fake UNIX epoch seconds */
Datum set_mock_time_epoch(PG_FUNCTION_ARGS) {
    double s = PG_GETARG_FLOAT8(0);
    long long whole = (long long) floor(s);
    long nsec = (long) ((s - (double)whole) * 1e9);
    
    write_config(true, false, whole, nsec, 0, 0);
    PG_RETURN_VOID();
}

/* Set offset in seconds */
Datum set_mock_time_offset_seconds(PG_FUNCTION_ARGS) {
    double s = PG_GETARG_FLOAT8(0);
    long long whole = (long long) (s >= 0 ? floor(s) : ceil(s));
    long nsec = (long) ((s - (double)whole) * 1e9);
    
    write_config(true, true, 0, 0, whole, nsec);
    PG_RETURN_VOID();
}

/* Disable mocking */
Datum clear_mock_time(PG_FUNCTION_ARGS) {
    write_config(false, false, 0, 0, 0, 0);
    PG_RETURN_VOID();
}

/* Status function */
Datum pg_mock_time_status(PG_FUNCTION_ARGS) {
    char buf[256];
    FILE *f = fopen(CONFIG_FILE, "r");
    
    if (!f) {
        snprintf(buf, sizeof(buf), "mock: disabled");
    } else {
        int enabled, use_offset;
        long long fixed_sec, off_sec;
        long fixed_nsec, off_nsec;
        
        int n = fscanf(f, "%d %d %lld %ld %lld %ld",
                       &enabled, &use_offset, &fixed_sec, &fixed_nsec, &off_sec, &off_nsec);
        fclose(f);
        
        if (n != 6 || !enabled) {
            snprintf(buf, sizeof(buf), "mock: disabled");
        } else if (use_offset) {
            snprintf(buf, sizeof(buf), "mock: enabled (offset) %lld s, %ld ns", off_sec, off_nsec);
        } else {
            snprintf(buf, sizeof(buf), "mock: enabled (fixed) %lld s, %ld ns (UNIX epoch)", fixed_sec, fixed_nsec);
        }
    }
    
    PG_RETURN_TEXT_P(cstring_to_text(buf));
}