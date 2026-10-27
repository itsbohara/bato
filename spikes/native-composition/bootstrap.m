#import <dispatch/dispatch.h>
#include <crt_externs.h>
#include <stdlib.h>
#include <string.h>
extern void BatoInstallNativeProbe(void);
__attribute__((constructor)) static void initialize_probe(void) {
    if (!getenv("BATO_NATIVE_PROBE")) return;
    int argc = *_NSGetArgc();
    char **argv = *_NSGetArgv();
    for (int i = 1; i < argc; ++i) {
        if (strncmp(argv[i], "--type=", 7) == 0 || strcmp(argv[i], "--type") == 0) return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ BatoInstallNativeProbe(); });
}
