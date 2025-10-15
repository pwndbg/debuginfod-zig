const std = @import("std");

const default_log_level = std.log.Level.info;
var logwriter_mutex = std.Thread.Mutex.Recursive.init;
var logwriter_was_inited = false;

const log_writer: *std.Io.Writer = &log_file_writer.interface;
var log_file_writer: std.fs.File.Writer = .{
    .interface = std.fs.File.Writer.initInterface(&.{}),
    .file = .{ .handle = -1 },
    .mode = .streaming,
};

pub fn setLogFile(file: ?std.fs.File) void {
    logwriter_mutex.lock();
    defer logwriter_mutex.unlock();

    if(file) |filen| {
        log_file_writer.file = filen;
    } else {
        log_file_writer.file = .{ .handle = -1 };
    }
}

fn lockLogWriter(buffer: []u8) ?*std.Io.Writer {
    if (log_file_writer.file.handle == -1) {
        return null;
    }
    logwriter_mutex.lock();
    log_writer.flush() catch {};
    log_writer.buffer = buffer;
    return log_writer;
}

fn unlockLogWriter() void {
    log_writer.flush() catch {};
    log_writer.end = 0;
    log_writer.buffer = &.{};
    logwriter_mutex.unlock();
}

fn log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(message_level) > @intFromEnum(default_log_level)) {
        return;
    }
    if(!logwriter_was_inited) {
        logwriter_was_inited = true;
        if(std.posix.getenv("DEBUGINFOD_VERBOSE") != null) {
            setLogFile(.stderr());
        }
    }

    var buffer: [64]u8 = undefined;
    if(lockLogWriter(&buffer)) |stderr| {
        defer unlockLogWriter();
        const level_txt = comptime message_level.asText();
        const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
        nosuspend stderr.print(level_txt ++ prefix2 ++ format ++ "\n", args) catch return;
    }
}

fn scoped(comptime scope: @Type(.enum_literal)) type {
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
