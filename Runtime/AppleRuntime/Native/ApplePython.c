// Python sources on iOS and tvOS: one CPython inside the app runs Runtime/PythonHost/host.py, the same
// host the Mac starts as a separate process (Docs/python-runtime-plan.md). The app does not link Python:
// it opens the Python.framework that Scripts/embed-apple-python.sh adds to the bundle, so a build without
// it still runs and simply offers no Python sources (EmbeddedPythonHost.available).
#include <dispatch/dispatch.h>
#include <dlfcn.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct _object PyObject;
typedef struct PyInitConfig PyInitConfig;

// The stable C API calls the bridge needs, looked up once. PyInitConfig (PEP 741) keeps the
// configuration opaque, so no Python headers or struct layouts are compiled in.
static struct {
    PyInitConfig *(*InitConfig_Create)(void);
    void (*InitConfig_Free)(PyInitConfig *);
    int (*InitConfig_GetError)(PyInitConfig *, const char **);
    int (*InitConfig_HasOption)(PyInitConfig *, const char *);
    int (*InitConfig_SetInt)(PyInitConfig *, const char *, int64_t);
    int (*InitConfig_SetStr)(PyInitConfig *, const char *, const char *);
    int (*InitializeFromInitConfig)(PyInitConfig *);
    int (*GILState_Ensure)(void);
    void (*GILState_Release)(int);
    void *(*Eval_SaveThread)(void);
    PyObject *(*Import_ImportModule)(const char *);
    PyObject *(*Sys_GetObject)(const char *);
    PyObject *(*Object_CallMethod)(PyObject *, const char *, const char *, ...);
    const char *(*Unicode_AsUTF8)(PyObject *);
    void (*DecRef)(PyObject *);
    void (*Err_Print)(void);
} py;

static dispatch_once_t started;
static PyObject *host;     // host.py, imported once and kept for the life of the process
static char failure[512];  // why Python could not start; every request answers with it

// A host-style error envelope; the app shows `error`.
static char *envelope(const char *message) {
    size_t length = strlen(message);
    char *output = malloc(length * 6 + 64), *cursor = output;
    cursor += sprintf(cursor, "{\"errorCode\":\"embedded_request\",\"error\":\"");
    for (const unsigned char *c = (const unsigned char *)message; *c; c++) {
        if (*c == '"' || *c == '\\') { *cursor++ = '\\'; *cursor++ = (char)*c; }
        else if (*c < 0x20) cursor += sprintf(cursor, "\\u%04x", *c);
        else *cursor++ = (char)*c;
    }
    strcpy(cursor, "\"}");
    return output;
}

static int load(const char *resources) {
    char path[PATH_MAX];
    snprintf(path, sizeof path, "%s/Frameworks/Python.framework/Python", resources);
    void *library = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    if (!library) {
        snprintf(failure, sizeof failure, "This build does not include the Python runtime (%s).", dlerror());
        return 0;
    }
#define SYMBOL(field, name) \
    if (!(*(void **)&py.field = dlsym(library, name))) { \
        snprintf(failure, sizeof failure, "The Python runtime lacks %s.", name); \
        return 0; \
    }
    SYMBOL(InitConfig_Create, "PyInitConfig_Create")
    SYMBOL(InitConfig_Free, "PyInitConfig_Free")
    SYMBOL(InitConfig_GetError, "PyInitConfig_GetError")
    SYMBOL(InitConfig_HasOption, "PyInitConfig_HasOption")
    SYMBOL(InitConfig_SetInt, "PyInitConfig_SetInt")
    SYMBOL(InitConfig_SetStr, "PyInitConfig_SetStr")
    SYMBOL(InitializeFromInitConfig, "Py_InitializeFromInitConfig")
    SYMBOL(GILState_Ensure, "PyGILState_Ensure")
    SYMBOL(GILState_Release, "PyGILState_Release")
    SYMBOL(Eval_SaveThread, "PyEval_SaveThread")
    SYMBOL(Import_ImportModule, "PyImport_ImportModule")
    SYMBOL(Sys_GetObject, "PySys_GetObject")
    SYMBOL(Object_CallMethod, "PyObject_CallMethod")
    SYMBOL(Unicode_AsUTF8, "PyUnicode_AsUTF8")
    SYMBOL(DecRef, "Py_DecRef")
    SYMBOL(Err_Print, "PyErr_Print")
#undef SYMBOL
    return 1;
}

static int configure(PyInitConfig *config, const char *resources) {
    char home[PATH_MAX], executable[PATH_MAX];
    uint32_t size = sizeof executable;
    snprintf(home, sizeof home, "%s/python", resources);
    // The config starts isolated: no environment variables, no user site-packages. The bundle is
    // signed and read-only, so bytecode is precompiled (build-apple-python.sh) and never written.
    // Extension modules are found through .fwork files relative to the executable's folder.
    if (py.InitConfig_SetStr(config, "home", home) < 0) return 0;
    if (_NSGetExecutablePath(executable, &size) == 0 && py.InitConfig_SetStr(config, "executable", executable) < 0) return 0;
    if (py.InitConfig_SetInt(config, "write_bytecode", 0) < 0) return 0;
    if (py.InitConfig_SetInt(config, "install_signal_handlers", 0) < 0) return 0;
    if (py.InitConfig_SetInt(config, "utf8_mode", 1) < 0) return 0;
    // print() and spider logs go to the unified log rather than nowhere.
    if (py.InitConfig_HasOption(config, "use_system_logger") && py.InitConfig_SetInt(config, "use_system_logger", 1) < 0) return 0;
    return 1;
}

static void start(void *context) {
    const char *resources = context;
    if (!load(resources)) return;
    // Python ignores these itself only when it installs signal handlers, which an app's Python must not.
    // Otherwise a write to a closed socket (the player leaving the media proxy, a server hanging up)
    // kills the app instead of raising BrokenPipeError. AppleRuntime.m does the same for the JVM.
    signal(SIGPIPE, SIG_IGN); signal(SIGXFSZ, SIG_IGN);
    PyInitConfig *config = py.InitConfig_Create();
    if (!config) { snprintf(failure, sizeof failure, "The Python runtime could not allocate its configuration."); return; }
    if (!configure(config, resources) || py.InitializeFromInitConfig(config) < 0) {
        const char *error = NULL;
        py.InitConfig_GetError(config, &error);
        snprintf(failure, sizeof failure, "The Python runtime could not start: %s", error ? error : "unknown error");
        py.InitConfig_Free(config);
        return;
    }
    py.InitConfig_Free(config);
    char folder[PATH_MAX];
    snprintf(folder, sizeof folder, "%s/PythonHost", resources);
    PyObject *path = py.Sys_GetObject("path");  // borrowed
    PyObject *inserted = path ? py.Object_CallMethod(path, "insert", "is", 0, folder) : NULL;
    if (inserted) py.DecRef(inserted);
    host = inserted ? py.Import_ImportModule("host") : NULL;
    if (!host) {
        py.Err_Print();
        snprintf(failure, sizeof failure, "The Python host could not load.");
    }
    // This thread took the GIL when it started Python; request threads take turns from now on.
    py.Eval_SaveThread();
}

// Answers one host request (JSON in, JSON out; see `handle` in host.py). The caller frees the result.
// Requests may come from any thread at once: each holds the GIL only while Python runs, and Python
// releases it while it waits on the network.
char *TVPythonRequest(const char *resources, const char *request) {
    dispatch_once_f(&started, (void *)resources, start);
    if (!host) return envelope(failure);
    int state = py.GILState_Ensure();
    PyObject *result = py.Object_CallMethod(host, "handle", "s", request);
    const char *text = result ? py.Unicode_AsUTF8(result) : NULL;
    char *output;
    if (text) output = strdup(text);
    else {
        py.Err_Print();
        output = envelope("The Python host failed to answer.");
    }
    if (result) py.DecRef(result);
    py.GILState_Release(state);
    return output;
}
