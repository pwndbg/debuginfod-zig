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

    const local_path = ctx.retryAllUrls(build_id_casted, client.DebuginfodContext.findDebuginfo) catch |err| {
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

    const local_path = ctx.retryAllUrls(build_id_casted, client.DebuginfodContext.findExecutable) catch |err| {
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

    const source_path_casted: []const u8 = std.mem.span(source_path);

    const local_path = ctx.findSource(build_id_casted, source_path_casted, ctx.urls[0]) catch |err| {
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
    const ctx = handle orelse return -1;

    const build_id_casted = helpers.build_id_to_hex(ctx.allocator, build_id, build_id_len) catch |err| {
        std.log.err("build_id_to_hex err: {}", .{err});
        return -1;
    };
    defer ctx.allocator.free(build_id_casted);

    const section_casted: []const u8 = std.mem.span(section);
    const local_path = ctx.findSection(build_id_casted, section_casted, ctx.urls[0]) catch |err| {
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
    const ctx = handle orelse return null;
    return ctx.current_userdata;
}

export fn debuginfod_get_url(
    handle: ?*client.DebuginfodContext,
) [*c]const c_char {
    const ctx = handle orelse return null;
    const url = ctx.current_url orelse {
        return null;
    };
    const allocator = ctx.fetch_allocator;
    const output = helpers.toCString(allocator, url) catch |err| {
        std.log.err("debuginfod_get_url err: {}", .{err});
        return null;
    };
    return @ptrCast(output.ptr);
}

export fn debuginfod_add_http_header(
    handle: ?*client.DebuginfodContext,
    header: [*c]const c_char,
) c_int {
    const ctx = handle orelse return -1;
    _ = ctx;
    const header_casted: []const u8 = std.mem.span(header);
    const colon_idx = std.mem.indexOf(u8, header_casted, ": ") orelse {
        return -1;
    };
    const out = std.http.Header{
        .name = header_casted[0..colon_idx],
        .value = header_casted[colon_idx+2..],
    };
    _ = out;
    // todo: append header

    return 0;
}

export fn debuginfod_get_headers(
    handle: ?*client.DebuginfodContext,
) [*c]const c_char {
    const ctx = handle orelse return null;
    const headers = ctx.last_headers;
    const allocator = ctx.fetch_allocator;

    var list = std.ArrayList(u8).initCapacity(allocator, 0) catch return null;
    for(headers) |header| {
        if(!std.mem.startsWith(u8, header.name, "x-debuginfod")) {
            continue;
        }
        list.appendSlice(allocator, header.name) catch return null;
        list.appendSlice(allocator, ": ") catch return null;
        list.appendSlice(allocator, header.value) catch return null;
        list.appendSlice(allocator, "\n") catch return null;
    }
    if(list.items.len == 0) {
        return null;
    }
    _ = list.pop();

    const output = list.toOwnedSliceSentinel(allocator, 0) catch return null;
    return @ptrCast(output.ptr);
}

export fn debuginfod_set_progressfn(
    handle: ?*client.DebuginfodContext,
    fnptr: ?*client.ProgressFnType,
) void {
    const ctx = handle orelse return;
    _ = ctx;
    _ = fnptr;
    // TODO: nice to have
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
    // TODO: nice to have
    return -1;
}
