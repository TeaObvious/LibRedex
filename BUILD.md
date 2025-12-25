# Build Instructions (libredex)

This repo now uses a modern, MXE-free CMake build with vendored dependencies. Outputs are placed in the legacy layout:

```
Binaries/Windows/<Debug|Release>/
Binaries/Linux/<Debug|Release>/
```

## Clone + Submodules

```bash
git submodule update --init --recursive
```

## Dependencies (Host Tools)

- CMake >= 3.20
- Ninja (recommended)
- C/C++ compiler (gcc/clang) with C++14 support
- For cross builds: mingw-w64 (x86_64-w64-mingw32 toolchain)

All third-party libraries used by libredex are vendored as git submodules under `third_party/`.

## Targets / Outputs

Target: `libredex` (output name depends on bitness)

- 64-bit (default):
  - Linux: `libredex_x64.so`
  - Windows: `libredex_x64.dll`
- 32-bit (optional):
  - Linux: `libredex.so`
  - Windows: `libredex.dll`

Outputs land in:

- `Binaries/Linux/<Debug|Release>/`
- `Binaries/Windows/<Debug|Release>/`

## Vendored Dependencies

- **Boost** (submodule `third_party/boost`)
  - Built via `bootstrap` + `b2` (ExternalProject) and staged under `build/third_party/boost/stage`
  - Libraries built/linked: filesystem, system, thread, random, regex
  - Also built/linked (optional but required by this codebase): chrono, date_time, atomic
- **MariaDB Connector/C** (submodule `third_party/mariadb-connector-c`)
  - Built from source, linked statically into the libredex DLL on Windows
  - Windows uses Schannel for TLS (no OpenSSL dependency)
  - Linux uses OpenSSL because Connector/C 3.4.x does not support disabling TLS entirely

Runtime DLLs:
- Windows: only system DLLs (no external `libmariadb.dll` required)
- Linux: libredex links dynamically to glibc/system libs only; Boost/MariaDB are built from submodules

## Linux Native Build

```bash
cmake --preset linux-debug
cmake --build --preset linux-debug

cmake --preset linux-release
cmake --build --preset linux-release
```

## Linux -> Windows Cross (mingw-w64)

The toolchain file is in `cmake/toolchains/mingw-w64-x86_64.cmake` and is used by the presets.

```bash
cmake --preset mingw64-debug
cmake --build --preset mingw64-debug

cmake --preset mingw64-release
cmake --build --preset mingw64-release
```

## Windows (MSYS2 MinGW-w64)

Use a **MinGW-w64** shell. Install packages such as:

```
pacman -S mingw-w64-x86_64-toolchain mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja
```

Then build:

```bash
cmake --preset msys2-mingw64-debug
cmake --build --preset msys2-mingw64-debug

cmake --preset msys2-mingw64-release
cmake --build --preset msys2-mingw64-release
```

## Smoke Test (version only)

The primary smoke test uses the Python interface under `libredex/python/interface` to call `RVExtensionArgs` with the `version` command.
If that interface cannot be used, create the `_smoketest_version.py` fallback script locally (do not commit) and run it.
