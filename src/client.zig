const std = @import("std");
const helpers = @import("helpers.zig");

pub const ProgressFnType = fn(handle: ?*DebuginfodContext, current: c_long, total: c_long) c_int;

pub const DebuginfodContext = struct {
    arena: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    urls: [1][]const u8,
    cache_path: []const u8,
    progress_fn: ?*ProgressFnType,

    pub fn init(base_allocator: std.mem.Allocator) !*DebuginfodContext {
        const arena = try base_allocator.create(std.heap.ArenaAllocator);
        errdefer base_allocator.destroy(arena);

        arena.* = std.heap.ArenaAllocator.init(base_allocator);
        const allocator = arena.allocator();

        // const urls_env = std.process.getEnvVarOwned(allocator, "DEBUGINFOD_URLS") catch |err| {
        //     if (err == .EnvironmentVariableNotFound) {
        //         null;
        //     } else {
        //         return err;
        //     }
        // };
        const urls = [_][]const u8{
            // "https://debuginfod.ubuntu.org",
            "https://debuginfod.debian.net",
        };

        const ctx = try allocator.create(DebuginfodContext);
        ctx.arena = arena;
        ctx.allocator = allocator;
        ctx.urls = urls;
        ctx.cache_path = "/tmp/"; // todo: env  // TODO: mkdir
        return ctx;
    }

    pub fn deinit(self: *DebuginfodContext) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
        self.* = undefined;
    }

    // router.GET("/buildid/:buildid/source/*path", proxyRequest)
    // router.GET("/buildid/:buildid/executable", proxyRequest)
    // router.GET("/buildid/:buildid/debuginfo", proxyRequest)

    pub fn findDebuginfo(self: *DebuginfodContext, build_id: []u8) ![]u8 {
        const full_url = try std.fmt.allocPrint(self.allocator, "{s}/buildid/{s}/debuginfo", .{self.urls[0], build_id});
        defer self.allocator.free(full_url);

        const local_path = try std.fmt.allocPrint(self.allocator, "{s}{s}.elf", .{self.cache_path, build_id});
        errdefer self.allocator.free(local_path);  // caller must free

        try helpers.fetchAsFile(self.allocator, full_url, local_path);
        return local_path;
    }
};
