#include <stdlib.h>
#include <string.h>
int main(int argc, char **argv) { const char *h = getenv("HAVE_GIT"); if (argc > 1 && !strcmp(argv[1], "git") && h && !strcmp(h, "0")) return 1; return 0; }
