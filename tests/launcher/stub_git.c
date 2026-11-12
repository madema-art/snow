#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static int envint(const char *n, int d) { const char *v = getenv(n); return v && *v ? atoi(v) : d; }
int main(int argc, char **argv) {
    const char *log = getenv("SNOW_TEST_LOG");
    if (log) { FILE *f = fopen(log, "a"); if (f) { fprintf(f, "git"); for (int i = 1; i < argc; i++) fprintf(f, " [%s]", argv[i]); fprintf(f, "\n"); fclose(f); } }
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "fetch")) return envint("GIT_FETCH_RC", 0);
        if (!strcmp(argv[i], "merge-base")) return envint("GIT_ANCESTOR_RC", 0);
        if (!strcmp(argv[i], "merge")) return envint("GIT_MERGE_RC", 0);
        if (!strcmp(argv[i], "rev-parse")) { const char *r = getenv("GIT_REV"); printf("%s\n", r && *r ? r : "abc123"); return 0; }
    }
    return 0;
}
