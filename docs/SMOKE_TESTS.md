# Smoke Tests

## Build commands

### MinGW32 release
```
cmake --preset mingw32-release
cmake --build --preset mingw32-release -v
```

### MinGW64 release
```
cmake --preset mingw64-release
cmake --build --preset mingw64-release -v
```

### Linux release
```
cmake --preset linux-release
cmake --build --preset linux-release
```

## Python smoke test
```
python - <<'PY'
from libredex.python.interface.extension import Extension
ext = Extension('Binaries/Linux/Release/libredex_x64.so')
print(ext.ExecuteAndPrint('version', []))
PY
```

Expected output pattern:
```
SENDING: [version, []]
OUTPUT: ["MSG", [1,2,0,0]]
["MSG", [1,2,0,0]]
```

## Checklist
- [ ] `mingw32-release` configure + build succeed
- [ ] `mingw64-release` configure + build succeed
- [ ] `linux-release` configure + build succeed
- [ ] Python smoke test output matches the expected pattern
