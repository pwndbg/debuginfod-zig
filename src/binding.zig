const std = @import("std");
const helpers = @import("helpers.zig");
const client = @import("client.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

export fn debuginfod_begin() ?*client.DebuginfodContext {
    std.log.err("debuginfod_begin enter", .{});

    const ctx = client.DebuginfodContext.init(std.heap.c_allocator) catch |err| {
        std.log.err("debuginfod_begin init err: {}", .{err});
        return null;
    };
    return ctx;
}

export fn debuginfod_end(handle: ?*client.DebuginfodContext) void {
    std.log.err("debuginfod_end enter", .{});

    const ctx = handle orelse return;
    defer ctx.deinit();
}

export fn debuginfod_find_debuginfo(
    handle: ?*client.DebuginfodContext,
    build_id: [*c]const u8,
    build_id_len: c_int,
    path_out_c: [*c][*c]c_char,
) c_int {
    const ctx = handle orelse return -1;

    const build_id_casted = helpers.build_id_to_hex(ctx.allocator, build_id, build_id_len) catch |err| {
        std.log.err("build_id_to_hex err: {}", .{err});
        return -1;
    };
    defer ctx.allocator.free(build_id_casted);
    std.log.err("debuginfod_find_debuginfo enter {s}", .{build_id_casted});

    const local_path = ctx.findDebuginfo(build_id_casted) catch |err| {
        std.log.err("findDebuginfo err: {}", .{err});
        return -1;
    };
    defer ctx.allocator.free(local_path);

    const fd = std.posix.open(local_path, .{
        .CLOEXEC = true,
        .ACCMODE = .RDONLY,
    }, 0) catch |err| {
        std.log.err("open err: {}", .{err});
        return -1;
    };

    const path_out = helpers.toCString(std.heap.c_allocator, local_path) catch |err| {
        std.log.err("findDebuginfo err: {}", .{err});
        return -1;
    };
    path_out_c.* = @ptrCast(path_out.ptr);
    return fd;
}

export fn debuginfod_find_executable(
    handle: ?*client.DebuginfodContext,
    build_id: [*c]const u8,
    build_id_len: c_int,
    path_out_c: [*c][*c]c_char,
) c_int {
    const ctx = handle orelse return -1;
    _ = ctx;
    _ = build_id;
    _ = build_id_len;
    _ = path_out_c;
    return -1;
}

export fn debuginfod_find_source(
    handle: ?*client.DebuginfodContext,
    build_id: [*c]const u8,
    build_id_len: c_int,
    source_path: [*c]const c_char,
    path_out_c: [*c][*c]c_char,
) c_int {
    const ctx = handle orelse return -1;
    _ = ctx;
    _ = build_id;
    _ = build_id_len;
    _ = source_path;
    _ = path_out_c;
    return -1;
}

export fn debuginfod_set_progressfn(
    handle: ?*client.DebuginfodContext,
    fnptr: ?*client.ProgressFnType,
) void {
    const ctx = handle orelse return;
    _ = ctx;
    _ = fnptr;
}

export fn debuginfod_set_user_data(
    handle: ?*client.DebuginfodContext,
    value: ?*anyopaque,
) void {
    const ctx = handle orelse return;
    _ = ctx;
    _ = value;
}

export fn debuginfod_get_user_data(
    handle: ?*client.DebuginfodContext,
) ?*anyopaque {
    const ctx = handle orelse return null;
    _ = ctx;
    return null;
}

export fn debuginfod_get_url(
    handle: ?*client.DebuginfodContext,
) [*c]const c_char {
    const ctx = handle orelse return null;
    _ = ctx;
    return null;
}

export fn debuginfod_add_http_header(
    handle: ?*client.DebuginfodContext,
    header: [*c]const c_char,
) c_int {
    const ctx = handle orelse return 0;
    _ = ctx;
    _ = header;
    return 0;
}

export fn debuginfod_set_verbose_fd(
    handle: ?*client.DebuginfodContext,
    fd: c_int,
) void {
    const ctx = handle orelse return;
    _ = ctx;
    _ = fd;
    return;
}

export fn debuginfod_get_headers(
    handle: ?*client.DebuginfodContext,
) [*c]const c_char {
    const ctx = handle orelse return null;
    _ = ctx;
    return null;
}

export fn debuginfod_find_section(
    handle: ?*client.DebuginfodContext,
    build_id: [*c]const u8,
    build_id_len: c_int,
    section: [*c]const c_char,
    path_out_c: [*c][*c]c_char,
) c_int {
    const ctx = handle orelse return -1;
    _ = ctx;
    _ = build_id;
    _ = build_id_len;
    _ = section;
    _ = path_out_c;
    return -1;
}

export fn debuginfod_find_metadata(
    handle: ?*client.DebuginfodContext,
    key: [*c]const u8,
    value: [*c]const u8,
    path_out_c: [*c][*c]c_char,
) c_int {
    const ctx = handle orelse return -1;
    _ = ctx;
    _ = key;
    _ = value;
    _ = path_out_c;
    return -1;
}
