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
    var arena = std.heap.ArenaAllocator.init(base_allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    if (std.fs.path.dirname(local_path)) |dirname| {
        try std.fs.cwd().makePath(dirname);
    }

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
    // TODO: tmpfile / movefile
}

// test "fetch ubuntu base tarball and save to file" {
//     const allocator = std.testing.allocator;
//
//     // const url = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.raw";
//     const url = "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-amd64.tar.gz";
//     const out_path = "ubuntu-base.tar.gz";
//
//     defer std.fs.cwd().deleteFile(out_path) catch {};
//
//     try fetchAsFile(allocator, url, out_path);
//
//     var file = try std.fs.cwd().openFile(out_path, .{});
//     defer file.close();
//
//     const size = try file.getEndPos();
//     try std.testing.expect(size > 10 * 1024); // > 10 KB
//
//     std.debug.print("Pobrano {d} bajtów do {s}\n", .{ size, out_path });
// }

pub fn toCString(allocator: std.mem.Allocator, s: []const u8) ![:0]u8 {
    const dup = try allocator.allocSentinel(u8, s.len, 0);
    @memcpy(dup, s);
    return dup;
}

pub fn escapeFilename(allocator: std.mem.Allocator, src: []const u8) ![]u8 {
    const prefix_size = "deadbeef-".len;
    var dest_len = src.len + prefix_size;
    const max_dest_len = std.fs.max_name_bytes / 2;
    if (dest_len > max_dest_len)
        dest_len = max_dest_len;

    var dest = try allocator.alloc(u8, dest_len);
    var wi: usize = dest_len - 1;
    var ri: usize = src.len - 1;

    while (true) {
        dest[wi] = switch (src[ri]) {
            'A'...'Z', 'a'...'z', '0'...'9', '.', '-', '_' => src[ri],
            else => '#',
        };
        if(ri == 0 or wi == 0) {
            break;
        }
        wi -= 1;
        ri -= 1;
    }

    // hash djb2 (DJBX33A)
    var hash: u32 = 5381;
    for (src) |ch| {
        hash = ((hash << 5) +% hash) +% ch;
    }

    _ = try std.fmt.bufPrint(dest[0..8], "{x:0<8}", .{hash});
    dest[8] = '-';
    return dest;
}

test "escape" {
    const allocator = std.testing.allocator;

    const out = try escapeFilename(allocator, "/root/foo.c");
    defer allocator.free(out);
    try std.testing.expectEqualStrings("7d1e797c-#root#foo.c", out);

    const out3 = try escapeFilename(allocator, "/usr/src/debug/bash-5.3.0-2.fc43.aarch64/shell.c");
    defer allocator.free(out3);
    try std.testing.expectEqualStrings("8612e4f5-#usr#src#debug#bash-5.3.0-2.fc43.aarch64#shell.c", out3);

    const out2 = try escapeFilename(allocator, "/root/too-long-name-aaaa-bbbb-cccc-dddd-eeee-ffff-gggg-hhhh-iiii-jjjj/kkkk/llll-mmmm-nnnn-oooo-pppp-qqqq-rrrr-ssss-tttt-wwww-uuuu-vvvv-xxxx-zzzz-0000-1111-2222-3333-4444-5555-6666-7777-8888.c");
    defer allocator.free(out2);
    try std.testing.expectEqualStrings("8b26663b-k#llll-mmmm-nnnn-oooo-pppp-qqqq-rrrr-ssss-tttt-wwww-uuuu-vvvv-xxxx-zzzz-0000-1111-2222-3333-4444-5555-6666-7777-8888.c", out2);
}

pub fn urlencodePart(allocator: std.mem.Allocator, part: []const u8) ![]u8 {
    var aw = try std.Io.Writer.Allocating.initCapacity(allocator, part.len);
    defer aw.deinit();

    const f = std.Uri.Component{ .raw = part };
    try f.formatUser(&aw.writer);

    return try aw.toOwnedSlice();
}

test "urlencode" {
    const allocator = std.testing.allocator;

    const out = try urlencodePart(allocator, "/root/foo.c");
    defer allocator.free(out);

    try std.testing.expectEqualStrings("%2Froot%2Ffoo.c", out);
}
