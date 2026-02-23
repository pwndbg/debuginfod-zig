# debuginfod-zig

`debuginfod-zig` is a lightweight, portable alternative to GNU's `debuginfod`, compatible with GNU debuginfod version 0.194.

## Why?

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
zig build -Dtarget=x86_64-linux-gnu -Doptimize=ReleaseSafe -Dlinkage=dynamic
zig build -Dtarget=aarch64-linux-gnu -Doptimize=ReleaseSafe -Dlinkage=dynamic

zig build -Dtarget=x86_64-macos -Doptimize=ReleaseSafe -Dlinkage=dynamic
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe -Dlinkage=dynamic
```

## How to replace GDB debuginfod with this repo?
```
nix build github:pwndbg/debuginfod-zig#dynamic
cp ./result/lib/libdebuginfod.so /usr/lib64/libdebuginfod.so.1

# OR use env `LD_PRELOAD`
LD_PRELOAD=./result/lib/libdebuginfod.so /usr/bin/gdb
```
> NOTE1: `/usr/lib64/libdebuginfod.so.1` path depends on your distribution

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


## `flake.nix` example usage:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    debuginfod-zig.url = "github:pwndbg/debuginfod-zig";
  };
  outputs =
    inputs@{
      self,
      nixpkgs,
      debuginfod-zig,
      ...
    }:
    let
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
      fun_pkgs =
        system:
        import nixpkgs {
          inherit system;
          overlays = [
            debuginfod-zig.overlays.default
            (final: prev: {
              gdb-with-debuginfod = (prev.gdb.override { enableDebuginfod = false; }).overrideAttrs( old: {
                 buildInputs = (old.buildInputs or []) ++ [
                    prev.libdebuginfod-zig-static
                 ];
                 configureFlags = (old.configureFlags or []) ++ [
                    "--with-debuginfod=yes"
                 ];
              });
            })
          ];
        };
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = (fun_pkgs system);
        in
        {
          gdb-with-debuginfod = pkgs.gdb-with-debuginfod;
        }
      );
    };
}
```
