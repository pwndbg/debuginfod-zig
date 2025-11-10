const std = @import("std");
const helpers = @import("helpers.zig");
const client = @import("client.zig");
const log = @import("log.zig");

const CErrNoFound = -@as(i32, @intFromEnum(std.posix.E.NOENT));
const CErrUnknown = -@as(i32, @intFromEnum(std.posix.E.INVAL));

const Mode = enum {
    Debuginfo,
    Executable,
    Source,
    Section,
};

fn debuginfod_find_common(
    handle: ?*client.DebuginfodContext,
    build_id: [*c]const u8,
    build_id_len: c_int,
    extra: ?[*c]const c_char, // np. source_path lub section
    mode: Mode,
    path_out_c: [*c][*c]c_char,
) c_int {
    const ctx = handle orelse return CErrUnknown;

    const build_id_hex = helpers.build_id_to_hex(ctx.allocator, build_id, build_id_len) catch |err| {
        log.warn("build_id_to_hex err: {}", .{err});
        return CErrUnknown;
    };
    defer ctx.allocator.free(build_id_hex);

    var local_path: []const u8 = undefined;
    switch (mode) {
        .Debuginfo => {
            local_path = ctx.findDebuginfo(build_id_hex) catch |err| {
                log.warn("findDebuginfo err: {}", .{err});
                return switch (err) {
                    error.FetchStatusNotFound => CErrNoFound,
                    else => CErrUnknown,
                };
            };
        },
        .Executable => {
            local_path = ctx.findExecutable(build_id_hex) catch |err| {
                log.warn("findExecutable err: {}", .{err});
                return switch (err) {
                    error.FetchStatusNotFound => CErrNoFound,
                    else => CErrUnknown,
                };
            };
        },
        .Source => {
            if (extra == null) return CErrUnknown;
            const source_path_casted: []const u8 = std.mem.span(@as([*c]const u8, @ptrCast(extra.?)));
            local_path = ctx.findSource(build_id_hex, source_path_casted) catch |err| {
                log.warn("findSource err: {}", .{err});
                return switch (err) {
                    error.FetchStatusNotFound => CErrNoFound,
                    else => CErrUnknown,
                };
            };
        },
        .Section => {
            if (extra == null) return CErrUnknown;
            const section_casted: []const u8 = std.mem.span(@as([*c]const u8, @ptrCast(extra.?)));
            local_path = ctx.findSectionWithFallback(build_id_hex, section_casted) catch |err| {
                log.warn("findSection err: {}", .{err});
                return switch (err) {
                    error.FetchStatusNotFound => CErrNoFound,
                    else => CErrUnknown,
                };
            };
        },
    }
    defer ctx.allocator.free(local_path);

    const fd = std.posix.open(local_path, .{
        .CLOEXEC = true,
        .ACCMODE = .RDONLY,
    }, 0) catch |err| {
        log.warn("open err: {}", .{err});
        return CErrUnknown;
    };

    const path_out = helpers.toCString(std.heap.c_allocator, local_path) catch |err| {
        log.warn("toCString err: {}", .{err});
        return CErrUnknown;
    };
    path_out_c.* = @ptrCast(path_out.ptr);
    return fd;
}

export fn debuginfod_begin() ?*client.DebuginfodContext {
    var penvs = std.process.getEnvMap(std.heap.c_allocator) catch |err| {
        log.warn("debuginfod_begin getEnvMap err: {}", .{err});
        return null;
    };
    defer penvs.deinit();

    const ctx = client.DebuginfodContext.init(std.heap.c_allocator, penvs) catch |err| {
        log.warn("debuginfod_begin init err: {}", .{err});
        return null;
    };
    return ctx;
}

export fn debuginfod_end(handle: ?*client.DebuginfodContext) void {
    const ctx = handle orelse return;
    defer ctx.deinit();
}

export fn debuginfod_find_debuginfo(
    handle: ?*client.DebuginfodContext,
    build_id: [*c]const u8,
    build_id_len: c_int,
    path_out_c: [*c][*c]c_char,
) c_int {
    return debuginfod_find_common(handle, build_id, build_id_len, null, .Debuginfo, path_out_c);
}

export fn debuginfod_find_executable(
    handle: ?*client.DebuginfodContext,
    build_id: [*c]const u8,
    build_id_len: c_int,
    path_out_c: [*c][*c]c_char,
) c_int {
    return debuginfod_find_common(handle, build_id, build_id_len, null, .Executable, path_out_c);
}

export fn debuginfod_find_source(
    handle: ?*client.DebuginfodContext,
    build_id: [*c]const u8,
    build_id_len: c_int,
    source_path: [*c]const c_char,
    path_out_c: [*c][*c]c_char,
) c_int {
    return debuginfod_find_common(handle, build_id, build_id_len, source_path, .Source, path_out_c);
}

export fn debuginfod_find_section(
    handle: ?*client.DebuginfodContext,
    build_id: [*c]const u8,
    build_id_len: c_int,
    section: [*c]const c_char,
    path_out_c: [*c][*c]c_char,
) c_int {
    // comptime std.debug.assert(@sizeOf(@TypeOf(section)) == 8);
    return debuginfod_find_common(handle, build_id, build_id_len, section, .Section, path_out_c);
}

export fn debuginfod_find_metadata(
    handle: ?*client.DebuginfodContext,
    key: [*c]const c_char,
    value: [*c]const c_char,
    path: [*c][*c]c_char,
) c_int {
    _ = handle;
    _ = key;
    _ = value;
    _ = path;
    return CErrUnknown;
}

export fn debuginfod_set_user_data(
    handle: ?*client.DebuginfodContext,
    value: ?*anyopaque,
) void {
    const ctx = handle orelse return;
    ctx.current_userdata = value;
}

export fn debuginfod_get_user_data(
    handle: ?*client.DebuginfodContext,
) ?*anyopaque {
    const ctx = handle orelse return null;
    return ctx.current_userdata;
}

export fn debuginfod_get_url(
    handle: ?*client.DebuginfodContext,
) [*c]const c_char {
    const ctx = handle orelse return null;
    const url = ctx.current_url orelse return null;
    return @ptrCast(url.ptr);
}

export fn debuginfod_get_headers(
    handle: ?*client.DebuginfodContext,
) [*c]const c_char {
    const ctx = handle orelse return null;
    const headers = ctx.current_response_headers orelse return null;
    const cbuf = headers.toBinding() catch return null;
    return @ptrCast(cbuf.ptr);
}

export fn debuginfod_add_http_header(
    handle: ?*client.DebuginfodContext,
    header: [*c]const c_char,
) c_int {
    const ctx = handle orelse return CErrUnknown;

    const header_casted: []const u8 = std.mem.span(@as([*c]const u8, @ptrCast(header)));
    const header_trimmed = std.mem.trim(u8, header_casted, " \t\r\n");
    const colon_idx = std.mem.indexOf(u8, header_trimmed, ": ") orelse {
        return CErrUnknown;
    };
    ctx.addRequestHeader(.{
        .name = header_casted[0..colon_idx],
        .value = header_casted[colon_idx + 2 ..],
    }) catch {
        return CErrUnknown;
    };
    return 0;
}

export fn debuginfod_set_progressfn(
    handle: ?*client.DebuginfodContext,
    fnptr: ?*client.ProgressFnType,
) void {
    const ctx = handle orelse return;
    ctx.progress_fn = fnptr;
}

export fn debuginfod_set_verbose_fd(
    handle: ?*client.DebuginfodContext,
    fd: c_int,
) void {
    const ctx = handle orelse return;
    _ = ctx;
    log.setLogFile(.{ .handle = fd });
}
