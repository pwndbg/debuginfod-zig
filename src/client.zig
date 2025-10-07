const std = @import("std");
const helpers = @import("helpers.zig");

pub const ProgressFnType = fn(handle: ?*DebuginfodContext, current: c_long, total: c_long) c_int;
pub const FindCallbackFnType = fn(handle: *DebuginfodContext, build_id: []u8, url: []const u8) anyerror![]u8;

// envs:
// done #define DEBUGINFOD_URLS_ENV_VAR "DEBUGINFOD_URLS"
// done #define DEBUGINFOD_CACHE_PATH_ENV_VAR "DEBUGINFOD_CACHE_PATH"
// todo: #define DEBUGINFOD_TIMEOUT_ENV_VAR "DEBUGINFOD_TIMEOUT"
// todo: #define DEBUGINFOD_PROGRESS_ENV_VAR "DEBUGINFOD_PROGRESS"
// todo: #define DEBUGINFOD_VERBOSE_ENV_VAR "DEBUGINFOD_VERBOSE"
// todo: #define DEBUGINFOD_RETRY_LIMIT_ENV_VAR "DEBUGINFOD_RETRY_LIMIT"
// todo: #define DEBUGINFOD_MAXSIZE_ENV_VAR "DEBUGINFOD_MAXSIZE"
// todo: #define DEBUGINFOD_MAXTIME_ENV_VAR "DEBUGINFOD_MAXTIME"
// todo: #define DEBUGINFOD_HEADERS_FILE_ENV_VAR "DEBUGINFOD_HEADERS_FILE"
// todo: #define DEBUGINFOD_IMA_CERT_PATH_ENV_VAR "DEBUGINFOD_IMA_CERT_PATH"

fn getUrls(allocator: std.mem.Allocator) ![][]const u8 {
    var list = try std.ArrayList([]const u8).initCapacity(allocator, 0);

    const urls_env = std.posix.getenv("DEBUGINFOD_URLS");
    if (urls_env) |urls_val| {
        // Split by spaces
        var it = std.mem.tokenizeAny(u8, urls_val, " ");
        while (it.next()) |url| {
            if (url.len == 0) continue;
            // fixme: url is dangling pointer?
            try list.append(allocator, url);
        }
    }
    if (list.items.len == 0) {
        // TODO: default const
        try list.append(allocator, "https://debuginfod.debian.net");
    }
    return try list.toOwnedSlice(allocator);
}

fn getCachePath(allocator: std.mem.Allocator) ![]const u8 {
    const cache_path_env = std.posix.getenv("DEBUGINFOD_CACHE_PATH");
    if (cache_path_env) |cache_path| {
        return try allocator.dupe(u8, cache_path);
    }

    const xdg_cache_env = std.posix.getenv("XDG_CACHE_HOME");
    if (xdg_cache_env) |cache_path| {
        return try std.fmt.allocPrint(allocator, "{s}/debuginfod_client/", .{cache_path});
    }

    const home_env = std.posix.getenv("HOME");
    if (home_env) |cache_path| {
        return try std.fmt.allocPrint(allocator, "{s}/.cache/debuginfod_client/", .{cache_path});
    }

    return error.EmptyCachePathEnv;
}

pub const DebuginfodContext = struct {
    arena: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    // "static" envs
    urls: [][]const u8,
    cache_path: []const u8,

    // "dynamic" options
    fetch_arena: *std.heap.ArenaAllocator,
    fetch_allocator: std.mem.Allocator,
    progress_fn: ?*ProgressFnType,
    current_userdata: ?*anyopaque,
    current_url: ?[]const u8,
    add_headers: []const std.http.Header,
    last_headers: []const std.http.Header,

    pub fn init(base_allocator: std.mem.Allocator) !*DebuginfodContext {
        const arena = try base_allocator.create(std.heap.ArenaAllocator);
        errdefer base_allocator.destroy(arena);
        arena.* = std.heap.ArenaAllocator.init(base_allocator);
        errdefer arena.deinit();
        const allocator = arena.allocator();

        const fetch_arena = try allocator.create(std.heap.ArenaAllocator);
        fetch_arena.* = std.heap.ArenaAllocator.init(allocator);
        const fetch_allocator = fetch_arena.allocator();

        const ctx = try allocator.create(DebuginfodContext);
        ctx.arena = arena;
        ctx.allocator = allocator;
        ctx.urls = try getUrls(allocator);
        ctx.cache_path = try getCachePath(allocator);

        ctx.fetch_arena = fetch_arena;
        ctx.fetch_allocator = fetch_allocator;
        ctx.progress_fn = null;
        ctx.current_userdata = null;
        ctx.current_url = null;
        ctx.add_headers = &[_] std.http.Header{};
        ctx.last_headers = &[_] std.http.Header{};
        return ctx;
    }

    pub fn deinit(self: *DebuginfodContext) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
        self.* = undefined;
    }

    pub fn retryAllUrls(self: *DebuginfodContext, build_id: []u8, comptime callback: FindCallbackFnType) ![]u8 {
        _ = self.fetch_arena.reset(.free_all);

        var lastError: anyerror = error.NotFound;
        for (self.urls) |url| {
            self.current_url = url;
            const local_path = callback(self, build_id, url) catch |err| {
                lastError = err;
                continue;
            };
            return local_path;
        }
        return lastError;
    }

    pub fn findDebuginfo(self: *DebuginfodContext, build_id: []u8, url: []const u8) ![]u8 {
        std.log.err("findDebuginfo {s} {s}", .{url, build_id});

        const local_path = try std.fs.path.join(self.allocator, &.{self.cache_path, build_id, "debuginfo"});
        errdefer self.allocator.free(local_path);  // caller must free

        // todo: first fetch from disk

        const full_url = try std.fmt.allocPrint(self.allocator, "{s}/buildid/{s}/debuginfo", .{url, build_id});
        defer self.allocator.free(full_url);

        try helpers.fetchAsFile(self.allocator, full_url, local_path);
        return local_path;
    }

    pub fn findExecutable(self: *DebuginfodContext, build_id: []u8, url: []const u8) ![]u8 {
        std.log.err("findExecutable {s} {s}", .{url, build_id});

        const local_path = try std.fs.path.join(self.allocator, &.{self.cache_path, build_id, "executable"});
        errdefer self.allocator.free(local_path);  // caller must free

        // todo: first fetch from disk

        const full_url = try std.fmt.allocPrint(self.allocator, "{s}/buildid/{s}/executable", .{url, build_id});
        defer self.allocator.free(full_url);

        try helpers.fetchAsFile(self.allocator, full_url, local_path);
        return local_path;
    }

    pub fn findSource(self: *DebuginfodContext, build_id: []u8, source_path: []const u8, url: []const u8) ![]u8 {
        std.log.err("findSource {s} {s} {s}", .{url, build_id, source_path});

        const source_path_encoded = try helpers.urlencodePart(self.allocator, source_path);
        defer self.allocator.free(source_path_encoded);

        const source_path_escaped = try helpers.escapeFilename(self.allocator, source_path);
        defer self.allocator.free(source_path_escaped);

        const cache_part = try std.mem.concat(self.allocator, u8, &.{"source-", source_path_escaped});
        defer self.allocator.free(cache_part);

        const local_path = try std.fs.path.join(self.allocator, &.{self.cache_path, build_id, cache_part});
        errdefer self.allocator.free(local_path);  // caller must free

        // todo: first fetch from disk

        const full_url = try std.fmt.allocPrint(self.allocator, "{s}/buildid/{s}/source/{s}", .{url, build_id, source_path_encoded});
        defer self.allocator.free(full_url);

        try helpers.fetchAsFile(self.allocator, full_url, local_path);
        return local_path;
    }

    pub fn findSection(self: *DebuginfodContext, build_id: []u8, section: []const u8, url: []const u8) ![]u8 {
        std.log.err("findSection {s} {s} {s}", .{url, build_id, section});

        const section_escaped = try helpers.escapeFilename(self.allocator, section);
        defer self.allocator.free(section_escaped);

        const cache_part = try std.mem.concat(self.allocator, u8, &.{"section-", section_escaped});
        defer self.allocator.free(cache_part);

        const local_path = try std.fs.path.join(self.allocator, &.{self.cache_path, build_id, cache_part});
        errdefer self.allocator.free(local_path);  // caller must free

        // todo: first fetch from disk

        const full_url = try std.fmt.allocPrint(self.allocator, "{s}/buildid/{s}/section/{s}", .{url, build_id, section});
        defer self.allocator.free(full_url);

        try helpers.fetchAsFile(self.allocator, full_url, local_path);
        return local_path;
    }
};
