# Plan: Python sources on iPhone, iPad and Apple TV

Status: proposed, not started · Updated: October 25, 2026 · Issue: #125

## Goal

Python spiders (`.py` type 3 sources and `py_` keys) work on iOS and tvOS the way they already work on
macOS, with one approach for every platform rather than one per platform.

## Where it stands

- **macOS:** works (experimental). `Scripts/build-python-host.sh` bundles CPython 3.12 with the
  libraries in `Runtime/PythonHost/requirements.txt`, and `LocalJarHost` runs `Runtime/PythonHost/host.py`
  as a separate process under `spider.sb`.
- **iOS and tvOS:** the app can't start a separate process, and `LocalJarHost` is macOS-only, so Python
  sources show "This source requires a Python runtime, which is not available on this platform."
- **All platforms:** `Site.runtime` (`Sources/TVCore/Models.swift`) decides by file extension. A Python
  spider behind a short link with no `.py` in it is treated as a JAR and fails, the Mac included.

## Decision: embed one CPython, build the C libraries ourselves

We already embed a JVM the same way. `Scripts/build-apple-jvm.sh` and `build-apple-libffi.sh` build
for `ios`, `ios-simulator`, `tvos` and `tvos-simulator`. `Runtime/AppleRuntime/Native/AppleRuntime.m`
exposes the JVM as one C call (`TVAppleRuntimeRequest`), and `EmbeddedJarHost` drives that call through
`SerializedPluginWorker`. Python gets the same shape: one static interpreter, one C entry point, and the
same four build targets.

What doesn't carry across platforms is binary wheels. tvOS has none for any compiled library, and iOS
has only some, so we compile every C library from source with our own scripts.

## Design

1. **Interpreter:** CPython 3.14 from BeeWare's
   [Python-Apple-support](https://github.com/beeware/Python-apple-support). It is the one maintained build
   that covers both iOS and tvOS (python.org's official build is iOS-only). It also includes OpenSSL,
   which `ssl` and `hashlib` need for `requests`. We link it statically and ship a trimmed standard
   library (no tests, idlelib, tkinter, ensurepip), precompiled, because the bundle is read-only.
2. **Bridge:** a C file next to `AppleRuntime.m`, for example `TVPythonRequest(resources, json)`. It
   starts the interpreter only when a Python source is first used, imports `host.py`, and passes JSON
   requests and responses. A Swift actor wraps it with `SerializedPluginWorker`, as `EmbeddedJarHost`
   does. `host.py`'s loopback media proxy runs on a thread inside the app. A spider that hangs is
   abandoned at its deadline, the same way the JVM watchdog handles one now. `HOME` and `TMPDIR` point
   into the app's Caches.
3. **Libraries:** built as static libraries with the same SDK and target table as `build-apple-libffi.sh`:
   - **Pure Python, used as is:** requests, urllib3, certifi, idna, charset-normalizer (its pure-Python
     fallback), beautifulsoup4, soupsieve, cssselect, pyquery.
   - **`_cffi_backend`:** builds against the libffi we already build.
   - **pycryptodome:** plain C. `Crypto/Util/_raw_api.py` loads its C code from `.so` files with
     `ffi.dlopen` or `ctypes.CDLL`, which iOS and tvOS don't allow for loose files. We link the C code
     into the app and patch `load_pycryptodome_raw_lib` to look the functions up in the process. Some
     shared helper symbols may need renaming so the modules can link together.
   - **lxml:** libxml2 and libxslt are plain C. The lxml sdist ships its generated C files, so no Cython
     is needed. We register `lxml.etree` and `lxml.html` as built-in modules.
   - **cryptography:** left out on iOS and tvOS at first. It needs Rust, and Rust's tvOS target is tier 3
     (nightly with `build-std`). Most spiders use `Crypto` (pycryptodome). We measure how many real
     sources import `cryptography` before doing anything for it.
4. **macOS:** keeps its separate, sandboxed Python process, since an embedded interpreter wouldn't have
   `spider.sb` around it. `host.py`, `base/` and the library versions are the same files on every
   platform, so a spider that works on the Mac should behave the same on iPhone and Apple TV. Pin the
   same library versions in both builds.
5. **Availability:** `LocalJarHost.available(.python)` (and `Site` status text) reports the embedded
   runtime on iOS and tvOS, so Python sources stop being filtered out there.

## Options ruled out

- **Per-platform wheels:** two packaging paths, and the tvOS one doesn't exist.
- **Pyodide (Python compiled to WebAssembly):** large, slow without a JIT, and doesn't fit QuickJS.
- **Converting Python to JavaScript, or Jython on our JVM:** Jython is Python 2.7, and conversion breaks
  on real spiders.
- **A remote Python server:** someone has to run it, it breaks offline use, and the user's requests go
  to a third party.

## Costs and risks

- **App size:** about 40–60 MB more per platform (the Mac host is 103 MB before trimming).
- **Memory on Apple TV:** the JVM and Python can both be resident. Python loads only when a Python
  source is used. Measure on a real Apple TV before release.
- **Speed:** one interpreter with one GIL. Spiders mostly wait on the network, which releases the GIL,
  so parallel searches still work. CPU-heavy spiders run one at a time.
- **Isolation:** on iOS and tvOS Python runs in the app process, with the same access to the app's
  container that JAR and JavaScript sources already have. The OS app sandbox still applies.
- **App Store rules:** same position as the existing JVM and QuickJS hosts (guideline 2.5.2 on
  downloaded code). No new kind of risk.
- **Effort:** about 2 weeks for iOS and tvOS together. Once iOS works, tvOS is mostly the same
  scripts with the tvOS SDK added.

## Phases (one PR each)

1. **Short-link detection.** When a type 3 `api` has no recognizable extension, check the downloaded
   content (for example a `from base.spider import` line) before treating it as a JAR. Small, and helps
   the Mac right away. Unit test in `Tests/TVCoreTests`.
2. **Interpreter and bridge.** `Scripts/build-apple-python.sh [ios|ios-simulator|tvos|tvos-simulator]`,
   the C bridge, the Swift host, and the pure-Python libraries. Extend SourceSweep
   (`Scripts/build-apple-source-sweep.sh`, `test-sources.py --apple-simulator`) to send Python requests
   through the embedded runtime, and port the fixture spider from `Scripts/test-python-host.py` to it.
3. **pycryptodome**, then **lxml** (libxml2, libxslt). Same sweep, plus import checks for
   `Crypto.Cipher.AES`, `lxml.etree` and `pyquery`.
4. **Measure and decide.** Run the sweep over real Python sources on the tvOS and iOS simulators, then on
   a device. Record which fail and why, then decide about `cryptography`.

Each phase passes `swift test` and `Scripts/verify.sh`.
