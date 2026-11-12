#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <direct.h>
int main(int argc, char **argv) {
    const char *log = getenv("SNOW_TEST_LOG");
    const char *path = NULL; int import = 0;
    if (log) { FILE *f = fopen(log, "a"); if (f) { fprintf(f, "godot"); for (int i = 1; i < argc; i++) fprintf(f, " [%s]", argv[i]); fprintf(f, "\n"); fclose(f); } }
    for (int i = 1; i < argc; i++) { if (!strcmp(argv[i], "--path") && i + 1 < argc) path = argv[i + 1]; if (!strcmp(argv[i], "--import")) import = 1; }
    if (import && path) { char b[1024]; snprintf(b, sizeof b, "%s\\.godot", path); _mkdir(b); snprintf(b, sizeof b, "%s\\.godot\\imported", path); _mkdir(b); }
    return 0;
}
