/* Standalone getlimits implementation for upstream GNU coreutils test suite compatibility */
#define _FILE_OFFSET_BITS 64
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <float.h>
#include <stdint.h>
#include <signal.h>
#include <sys/types.h>
#include <stdbool.h>

#ifndef TIME_T_MAX
# define TIME_T_MAX ((time_t)((((time_t)1 << (sizeof(time_t)*8 - 2)) - 1) * 2 + 1))
#endif
#ifndef TIME_T_MIN
# define TIME_T_MIN (-TIME_T_MAX - 1)
#endif

#ifndef SSIZE_MAX
# define SSIZE_MAX ((ssize_t)((((size_t)1 << (sizeof(ssize_t)*8 - 1)) - 1)))
#endif
#ifndef SSIZE_MIN
# define SSIZE_MIN (-SSIZE_MAX - 1)
#endif

#ifndef PID_T_MAX
# define PID_T_MAX ((pid_t)((((pid_t)1 << (sizeof(pid_t)*8 - 2)) - 1) * 2 + 1))
#endif
#ifndef PID_T_MIN
# define PID_T_MIN ((pid_t)0)
#endif

#ifndef UID_T_MAX
# define UID_T_MAX ((uid_t)-1)
#endif
#ifndef GID_T_MAX
# define GID_T_MAX ((gid_t)-1)
#endif

#ifndef OFF_T_MAX
# define OFF_T_MAX ((off_t)((((off_t)1 << (sizeof(off_t)*8 - 2)) - 1) * 2 + 1))
#endif
#ifndef OFF_T_MIN
# define OFF_T_MIN (-OFF_T_MAX - 1)
#endif

#ifndef OFF64_T_MAX
# define OFF64_T_MAX ((int64_t)0x7fffffffffffffffLL)
#endif
#ifndef OFF64_T_MIN
# define OFF64_T_MIN (-OFF64_T_MAX - 1LL)
#endif

#ifndef SIGRTMIN
# define SIGRTMIN 34
#endif
#ifndef SIGRTMAX
# define SIGRTMAX 64
#endif

#ifndef IO_BUFSIZE
# define IO_BUFSIZE (128 * 1024)
#endif

static char const *decimal_absval_add_one(char *buf) {
    bool negative = (buf[1] == '-');
    char *absnum = buf + 1 + negative;
    char *p = absnum + strlen(absnum);
    absnum[-1] = '0';
    while (*--p == '9') {
        *p = '0';
    }
    ++*p;
    char *result = (absnum < p) ? absnum : p;
    if (negative) {
        *--result = '-';
    }
    return result;
}

static void print_val(const char *name, uintmax_t max_val, intmax_t min_val, bool has_min) {
    char limit[128];
    sprintf(limit + 1, "%ju", max_val);
    printf("%s_MAX=%s\n", name, limit + 1);
    printf("%s_OFLOW=%s\n", name, decimal_absval_add_one(limit));
    if (has_min && min_val != 0) {
        sprintf(limit + 1, "%jd", min_val);
        printf("%s_MIN=%s\n", name, limit + 1);
        printf("%s_UFLOW=%s\n", name, decimal_absval_add_one(limit));
    }
}

int main(int argc, char **argv) {
    if (argc > 1) {
        if (strcmp(argv[1], "--help") == 0) {
            printf("Usage: getlimits\nOutput platform dependent limits.\n");
            return (fflush(stdout) != 0 || ferror(stdout)) ? 1 : 0;
        }
        if (strcmp(argv[1], "--version") == 0) {
            printf("getlimits (coreutilz) 0.1.0\n");
            return (fflush(stdout) != 0 || ferror(stdout)) ? 1 : 0;
        }
    }

    print_val("CHAR", (uintmax_t)CHAR_MAX, (intmax_t)CHAR_MIN, CHAR_MIN != 0);
    print_val("SCHAR", (uintmax_t)SCHAR_MAX, (intmax_t)SCHAR_MIN, true);
    print_val("UCHAR", (uintmax_t)UCHAR_MAX, 0, false);
    print_val("SHRT", (uintmax_t)SHRT_MAX, (intmax_t)SHRT_MIN, true);
    print_val("INT", (uintmax_t)INT_MAX, (intmax_t)INT_MIN, true);
    print_val("UINT", (uintmax_t)UINT_MAX, 0, false);
    print_val("LONG", (uintmax_t)LONG_MAX, (intmax_t)LONG_MIN, true);
    print_val("ULONG", (uintmax_t)ULONG_MAX, 0, false);
    print_val("SIZE", (uintmax_t)SIZE_MAX, 0, false);
    print_val("SSIZE", (uintmax_t)SSIZE_MAX, (intmax_t)SSIZE_MIN, true);
    print_val("TIME_T", (uintmax_t)TIME_T_MAX, (intmax_t)TIME_T_MIN, true);
    print_val("UID_T", (uintmax_t)UID_T_MAX, 0, false);
    print_val("GID_T", (uintmax_t)GID_T_MAX, 0, false);
    print_val("PID_T", (uintmax_t)PID_T_MAX, (intmax_t)PID_T_MIN, false);
    print_val("OFF_T", (uintmax_t)OFF_T_MAX, (intmax_t)OFF_T_MIN, true);
    print_val("OFF64_T", (uintmax_t)OFF64_T_MAX, (intmax_t)OFF64_T_MIN, true);
    print_val("INTMAX", (uintmax_t)INTMAX_MAX, (intmax_t)INTMAX_MIN, true);
    print_val("UINTMAX", (uintmax_t)UINTMAX_MAX, 0, false);

    printf("FLT_MIN=%.10e\n", FLT_MIN);
    printf("FLT_MAX=%.10e\n", FLT_MAX);
    printf("DBL_MIN=%.17e\n", DBL_MIN);
    printf("DBL_MAX=%.17e\n", DBL_MAX);
    printf("LDBL_MIN=%.21Le\n", LDBL_MIN);
    printf("LDBL_MAX=%.21Le\n", LDBL_MAX);

    printf("SIGRTMIN=%jd\n", (intmax_t)SIGRTMIN);
    printf("SIGRTMAX=%jd\n", (intmax_t)SIGRTMAX);
    printf("IO_BUFSIZE=%ju\n", (uintmax_t)IO_BUFSIZE);

    return (fflush(stdout) != 0 || ferror(stdout)) ? 1 : 0;
}
