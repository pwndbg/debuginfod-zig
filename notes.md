
zig build -Dtarget=x86_64-linux-gnu
zig build -Dtarget=aarch64-linux-gnu


what is missing:
- cleanup cache
- store as tmp file + move
- ima policies/verification
- (target_cache_dir, 0700)
- missing `/hdr-debuginfo` (http response headers)

cp /work/zig-out/lib/libdebuginfo.so.1.0.192 /usr/lib64/libdebuginfod.so.1
gdb -ex 'set debuginfod enabled on' -ex 'set debuginfod urls https://debuginfod.debian.net' -ex 'set debuginfod verbose 1' -q -ex 'file /bin/bash'

https://debuginfod.fedoraproject.org/buildid/66cd4a67b80dfe2c59b7cfdccb4cb31c34cbc7a3/source/usr%2fsrc%2fdebug%2fbash-5.3.0-2.fc43.aarch64%2fshell.c


//debuginfod.debian.net/buildid/bea6a154d9a9158114ee0a2a439045596615df14/source/.