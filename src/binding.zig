const std = @import("std");
const helpers = @import("helpers.zig");
const client = @import("client.zig");

pub const std_options: std.Options = .{
    .log_level = .debug,
};

export fn debuginfod_begin() ?*client.DebuginfodContext {
    std.log.info("debuginfod_begin enter", .{});

    const ctx = client.DebuginfodContext.init(std.heap.c_allocator) catch |err| {
        std.log.err("debuginfod_begin init err: {}", .{err});
        return null;
    };
    return ctx;
}

export fn debuginfod_end(handle: ?*client.DebuginfodContext) void {
    std.log.info("debuginfod_end enter", .{});

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
        std.log.err("findDebuginfo err2: {}", .{err});
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

    const build_id_casted = helpers.build_id_to_hex(ctx.allocator, build_id, build_id_len) catch |err| {
        std.log.err("build_id_to_hex err: {}", .{err});
        return -1;
    };
    defer ctx.allocator.free(build_id_casted);

    const local_path = ctx.findExecutable(build_id_casted) catch |err| {
        std.log.err("findExecutable err: {}", .{err});
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
        std.log.err("findExecutable err2: {}", .{err});
        return -1;
    };
    path_out_c.* = @ptrCast(path_out.ptr);
    return fd;
}

export fn debuginfod_find_source(
    handle: ?*client.DebuginfodContext,
    build_id: [*c]const u8,
    build_id_len: c_int,
    source_path: [*c]const c_char,
    path_out_c: [*c][*c]c_char,
) c_int {
    const ctx = handle orelse return -1;

    const build_id_casted = helpers.build_id_to_hex(ctx.allocator, build_id, build_id_len) catch |err| {
        std.log.err("build_id_to_hex err: {}", .{err});
        return -1;
    };
    defer ctx.allocator.free(build_id_casted);

    const source_path_casted: []const u8 = std.mem.span(@as([*c]const u8, @ptrCast(source_path)));
    const local_path = ctx.findSource(build_id_casted, source_path_casted) catch |err| {
        std.log.err("findSource err: {}", .{err});
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
        std.log.err("findSource err2: {}", .{err});
        return -1;
    };
    path_out_c.* = @ptrCast(path_out.ptr);
    return fd;
}

export fn debuginfod_find_section(
    handle: ?*client.DebuginfodContext,
    build_id: [*c]const u8,
    build_id_len: c_int,
    section: [*c]const c_char,
    path_out_c: [*c][*c]c_char,
) c_int {
    comptime std.debug.assert(@sizeOf(@TypeOf(section)) == 8);
    const ctx = handle orelse return -1;

    const build_id_casted = helpers.build_id_to_hex(ctx.allocator, build_id, build_id_len) catch |err| {
        std.log.err("build_id_to_hex err: {}", .{err});
        return -1;
    };
    defer ctx.allocator.free(build_id_casted);

    const section_casted: []const u8 = std.mem.span(@as([*c]const u8, @ptrCast(section)));
    const local_path = ctx.findSectionWithFallback(build_id_casted, section_casted) catch |err| {
        std.log.err("findSection err: {}", .{err});
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
        std.log.err("findSection err2: {}", .{err});
        return -1;
    };
    path_out_c.* = @ptrCast(path_out.ptr);
    return fd;
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
    // std.log.info("debuginfod_get_user_data enter", .{});

    const ctx = handle orelse return null;
    return ctx.current_userdata;
}

export fn debuginfod_get_url(
    handle: ?*client.DebuginfodContext,
) [*c]const c_char {
    // std.log.info("debuginfod_get_url enter", .{});

    const ctx = handle orelse return null;
    const url = ctx.current_url orelse return null;
    return @ptrCast(url.ptr);
}

export fn debuginfod_get_headers(
    handle: ?*client.DebuginfodContext,
) [*c]const c_char {
    // std.log.info("debuginfod_get_headers enter", .{});

    const ctx = handle orelse return null;
    const headers = ctx.current_response_headers orelse return null;
    const cbuf = headers.toBinding() catch return null;
    return @ptrCast(cbuf.ptr);
}

export fn debuginfod_add_http_header(
    handle: ?*client.DebuginfodContext,
    header: [*c]const c_char,
) c_int {
    const ctx = handle orelse return -1;

    const header_casted: []const u8 = std.mem.span(@as([*c]const u8, @ptrCast(header)));
    const colon_idx = std.mem.indexOf(u8, header_casted, ": ") orelse {
        return -1;
    };
    const out = std.http.Header{
        .name = header_casted[0..colon_idx],
        .value = header_casted[colon_idx+2..],
    };
    _ = out;
    _ = ctx;
    // todo: append header

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
    _ = fd;
    // TODO: nice to have
    return;
}
