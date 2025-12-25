# Smoke Tests – LibRedex

This document defines the **mandatory smoke tests** for LibRedex.
Any change that claims “build is fixed” or “cross-compile works” **must pass all tests below**.

Automated agents (e.g. Codex) **may extend this file** with additional smoke tests,
but **must not weaken or remove existing ones**.

---

## 1. Build Smoke Tests

### 1.1 MinGW-w64 (Linux → Windows) cross compile

The MinGW builds must be executed **separately** for 32-bit and 64-bit.
There is intentionally **no combined CMake workflow**, because CMake workflows
do not allow multiple configure steps.

#### MinGW 32-bit (Release)

```bash
cmake --preset mingw32-release
cmake --build --preset mingw32-release -v
```

**Expected result**
- Configure succeeds
- Build succeeds
- No attempt to execute Windows-only tools on Linux (e.g. `bootstrap.bat`)

#### MinGW 64-bit (Release)

```bash
cmake --preset mingw64-release
cmake --build --preset mingw64-release -v
```

**Expected result**
- Configure succeeds
- Build succeeds
- Same toolchain logic as 32-bit, but using `x86_64-w64-mingw32-*`

---

### 1.2 Linux native build (Release)

The Linux native build must continue to work at all times.

```bash
cmake --preset linux-release
cmake --build --preset linux-release
```

**Expected result**
- Build succeeds
- Produces `Binaries/Linux/Release/libredex_x64.so`

---

## 2. Python Runtime Smoke Test (MANDATORY)

This is the **primary functional smoke test**.
If this fails, the build is considered broken, even if compilation succeeded.

### 2.1 Test command

```bash
python - <<'PY'
from libredex.python.interface.extension import Extension

ext = Extension('Binaries/Linux/Release/libredex_x64.so')
print(ext.ExecuteAndPrint('version', []))
PY
```

### 2.2 Expected output

The output must match this structure and values:

```
SENDING: [version, []]
OUTPUT: ["MSG", [1,2,0,0]]
["MSG", [1,2,0,0]]
```

Notes:
- The version tuple `[1,2,0,0]` must be preserved unless a **deliberate version bump**
  is part of the change.
- Formatting differences are acceptable **only** if the semantic content is identical.

---

## 3. Known Failure Classes (Regression Guards)

These issues have occurred in the past and must **not reappear**.

### 3.1 Boost cross compile on Linux

- Linux must **never** attempt to execute:
  ```
  third_party/boost/bootstrap.bat
  ```
- Host-based detection must be used:
  - ✔ `CMAKE_HOST_WIN32`
  - ✔ `CMAKE_HOST_SYSTEM_NAME`
  - ✘ `WIN32` (target-based) alone is incorrect for cross compile

### 3.2 MariaDB connector cross compile

Typical past failure:
```
conflicting types for ‘mysql_load_plugin’
```

If this reappears:
- Investigate header selection, include order, and compile definitions
- Fix must be reproducible and minimal
- Prefer CMake definitions or a small vendored patch applied from CMake

---

## 4. Extension Policy for This File

Automated agents (e.g. Codex) **may**:
- Add new smoke tests
- Add new regression notes
- Add platform-specific notes

Automated agents **must not**:
- Remove existing tests
- Downgrade mandatory tests to optional
- Change expected outputs without explicit justification

When in doubt:
> Add new tests, don’t relax old ones.

---

## 5. Definition of “Green”

A change is considered **successful** only if **all** of the following are true:

- ✅ MinGW32 release build succeeds
- ✅ MinGW64 release build succeeds
- ✅ Linux release build succeeds
- ✅ Python runtime smoke test produces the expected output

Anything less is **not green**.
