const std = @import("std");

// todo: MAX_BUILD_ID_BYTES 64
pub fn build_id_to_hex(allocator: std.mem.Allocator, build_id: [*c]const u8, build_id_len: c_int) ![]u8 {
    if (build_id_len == 0) {
        // build_id is hex lowercase already
        return try allocator.dupe(u8, std.mem.span(build_id));
    } else {
        // build_id is raw bytes
        const build_id_bytes = build_id[0..@as(usize, @intCast(build_id_len))];
        const buf = try allocator.alloc(u8, build_id_bytes.len*2);
        _ = try std.fmt.bufPrint(buf, "{x}", .{build_id_bytes});
        return buf;
    }
}

test "build_id_to_hex works for hex string input" {
    const allocator = std.testing.allocator;

    const hex_str = "4a7c2";
    const out = try build_id_to_hex(allocator, &hex_str[0], 0);

    std.debug.print("Hex string output: {s}\n", .{out});
    defer allocator.free(out);

    try std.testing.expect(std.mem.eql(u8, out, "4a7c2"));
}

test "build_id_to_hex works for raw bytes input" {
    const allocator = std.testing.allocator;

    const raw_bytes = [_]u8{0x4a, 0x7c, 0x2f};
    const out = try build_id_to_hex(allocator, &raw_bytes[0], raw_bytes.len);

    std.debug.print("Raw bytes to hex output: {s}\n", .{out});
    defer allocator.free(out);

    try std.testing.expect(std.mem.eql(u8, out, "4a7c2f"));
}

pub fn fetchAsFile(base_allocator: std.mem.Allocator, full_url: []const u8, local_path: []const u8) !void {
    // #define DEBUGINFOD_URLS_ENV_VAR "DEBUGINFOD_URLS"
    // #define DEBUGINFOD_CACHE_PATH_ENV_VAR "DEBUGINFOD_CACHE_PATH"
    // todo: #define DEBUGINFOD_TIMEOUT_ENV_VAR "DEBUGINFOD_TIMEOUT"
    // todo: #define DEBUGINFOD_PROGRESS_ENV_VAR "DEBUGINFOD_PROGRESS"
    // #define DEBUGINFOD_VERBOSE_ENV_VAR "DEBUGINFOD_VERBOSE"
    // todo: #define DEBUGINFOD_RETRY_LIMIT_ENV_VAR "DEBUGINFOD_RETRY_LIMIT"
    // todo: #define DEBUGINFOD_MAXSIZE_ENV_VAR "DEBUGINFOD_MAXSIZE"
    // todo: #define DEBUGINFOD_MAXTIME_ENV_VAR "DEBUGINFOD_MAXTIME"
    // todo: #define DEBUGINFOD_HEADERS_FILE_ENV_VAR "DEBUGINFOD_HEADERS_FILE"
    // #define DEBUGINFOD_IMA_CERT_PATH_ENV_VAR "DEBUGINFOD_IMA_CERT_PATH"
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var file = try std.fs.cwd().createFile(local_path, .{
        .truncate = true,
    });
    defer file.close();

    var client = std.http.Client{
        .allocator = allocator,
    };
    defer client.deinit();
    // var buffer: [64 * 1024]u8 = undefined; // BUG: https://github.com/ziglang/zig/pull/25235
    var buffer: [0]u8 = undefined;
    var writer = file.writer(&buffer);

    const resp = try client.fetch(.{
        .method = .GET,
        .location = .{
            .url = full_url,
        },
        .response_writer = &writer.interface,
    });
    if (resp.status != .ok) {
        return error.InvalidStatusCode;
    }
}

test "fetch ubuntu base tarball and save to file" {
    const allocator = std.testing.allocator;

    // const url = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.raw";
    const url = "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-amd64.tar.gz";
    const out_path = "ubuntu-base.tar.gz";

    defer std.fs.cwd().deleteFile(out_path) catch {};

    try fetchAsFile(allocator, url, out_path);

    var file = try std.fs.cwd().openFile(out_path, .{});
    defer file.close();

    const size = try file.getEndPos();
    try std.testing.expect(size > 10 * 1024); // > 10 KB

    std.debug.print("Pobrano {d} bajtów do {s}\n", .{ size, out_path });
}

pub fn toCString(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const dup = try allocator.allocSentinel(u8, s.len, 0);
    @memcpy(dup, s);
    return dup;
}
