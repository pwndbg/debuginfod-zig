
## Why?
`debuginfod-zig` was created as a lightweight, portable alternative to GNU's debuginfod.

While `debuginfod` works well only on Linux, it comes with several limitations that make it less practical in other environments or for static builds.

| Problem with GNU `debuginfod` | How `debuginfod-zig` solves it                                                                      |
|-------------------------------|-----------------------------------------------------------------------------------------------------|
| ❌ **No static builds** – cannot be compiled statically. | ✅ **Supports static builds** – fully self-contained binary.                                         |
| ❌ **Heavy dependency chain** – depends on `libcurl`, `sqlite`, `libelf`, and many others. | ✅ **No external dependencies** – written in pure **Zig**, minimal footprint.                        |
| ❌ **Linux-only** – cannot be built or used on macOS. | ✅ **Cross-platform** – works on **Linux** and **macOS**.                                            |
| ❌ **Broken source path handling** – only supports absolute paths (`/path/to/file.c`). | ✅ **Flexible source resolution** – supports both relative (`./build/../file.c`) and absolute paths. |
| ❌ **Written in C** – complex dependency management and less safe by design. | ✅ **Implemented in Zig** – safer, simpler, and easier to maintain.                                  |


## Build
```
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe
zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSafe

zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe
```

## ENV's implemented:
- DEBUGINFOD_URLS
- DEBUGINFOD_CACHE_PATH
- DEBUGINFOD_MAXTIME
- DEBUGINFOD_MAXSIZE

## ENV's not-implemented:
- DEBUGINFOD_TIMEOUT (hard)
- DEBUGINFOD_RETRY_LIMIT (easy)
- DEBUGINFOD_PROGRESS (easy)
- DEBUGINFOD_VERBOSE (easy)
- DEBUGINFOD_HEADERS_FILE (medium)
- DEBUGINFOD_IMA_CERT_PATH (hard?)

## What is missing:
- auto-cleanup old debuginfo files
- ima policies/verification
- caching headers as file `/hdr-debuginfo`
