const std = @import("std");

const default_log_level = std.log.Level.info;
// `std.Thread.Mutex` was removed; use the lock-free `std.atomic.Mutex`
// (tryLock/unlock) with a short spin. Contention is rare and held only for a
// single format+write.
var logwriter_mutex: std.atomic.Mutex = .unlocked;
var logwriter_was_inited = false;

fn lockMutex() void {
    while (!logwriter_mutex.tryLock()) {}
}

// Logging target fd (-1 == disabled).
var log_fd: std.posix.fd_t = -1;

pub fn setLogFile(file: ?std.Io.File) void {
    lockMutex();
    defer logwriter_mutex.unlock();

    log_fd = if (file) |f| f.handle else -1;
}

fn log(
    comptime message_level: std.log.Level,
    comptime scope: @EnumLiteral(),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(message_level) > @intFromEnum(default_log_level)) {
        return;
    }

    lockMutex();
    defer logwriter_mutex.unlock();

    if (!logwriter_was_inited) {
        logwriter_was_inited = true;
        if (std.c.getenv("DEBUGINFOD_VERBOSE") != null) {
            log_fd = std.Io.File.stderr().handle;
        }
    }
    if (log_fd == -1) {
        return;
    }

    // Mirror std.log's defaultLog: format into a small buffer-backed file
    // writer and flush before returning. `std.Options.debug_io` provides an
    // `Io` usable from logging contexts that don't otherwise have one (the
    // target fd may be a pipe/terminal, so use streaming mode). Locking keeps
    // concurrent log lines from interleaving.
    const io = std.Options.debug_io;
    const file: std.Io.File = .{ .handle = log_fd, .flags = .{ .nonblocking = false } };
    var buffer: [256]u8 = undefined;
    var file_writer = file.writerStreaming(io, &buffer);
    const writer = &file_writer.interface;

    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    nosuspend writer.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
    writer.flush() catch {};
}

fn scoped(comptime scope: @EnumLiteral()) type {
    return struct {
        pub fn err(
            comptime format: []const u8,
            args: anytype,
        ) void {
            @branchHint(.cold);
            log(.err, scope, format, args);
        }

        pub fn warn(
            comptime format: []const u8,
            args: anytype,
        ) void {
            log(.warn, scope, format, args);
        }

        pub fn info(
            comptime format: []const u8,
            args: anytype,
        ) void {
            log(.info, scope, format, args);
        }

        pub fn debug(
            comptime format: []const u8,
            args: anytype,
        ) void {
            log(.debug, scope, format, args);
        }
    };
}

const default = scoped(.debuginfod_zig);

pub const err = default.err;
pub const warn = default.warn;
pub const info = default.info;
pub const debug = default.debug;
