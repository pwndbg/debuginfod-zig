## Compatibility
- `debuginfod-zig` is compatible with GNU `debuginfod` version `0.194`

## Why?
`debuginfod-zig` was created as a lightweight, portable alternative to GNU's `debuginfod`.

While GNU `debuginfod` works well only on Linux, it comes with several limitations that make it less practical in other environments or for static builds.

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

# How to replace GDB debuginfod with this repo?
```
git clone https://github.com/pwndbg/debuginfod-zig
cd debuginfod-zig
zig build -Doptimize=ReleaseSafe -Dlinkage=dynamic
cp ./zig-out/lib/libdebuginfo.so /usr/lib64/libdebuginfod.so.1
```
> NOTE1: please download zig 0.16.0 - https://ziglang.org/download/

> NOTE2: `/usr/lib64/libdebuginfod.so.1` path depends on your distribution

## ENV's implemented:
- DEBUGINFOD_URLS
- DEBUGINFOD_CACHE_PATH
- DEBUGINFOD_MAXTIME
- DEBUGINFOD_MAXSIZE
- DEBUGINFOD_VERBOSE
- DEBUGINFOD_PROGRESS
- DEBUGINFOD_HEADERS_FILE
- DEBUGINFOD_TIMEOUT

## ENV's not-implemented:
- DEBUGINFOD_IMA_CERT_PATH (hard?)
- DEBUGINFOD_RETRY_LIMIT

## What is missing:
- missing func debuginfod_find_metadata
- auto-cleanup old debuginfo files
- ima policies/verification
- caching headers as file `/hdr-debuginfo`
- http connection is cancelable only after successful connect
