const std = @import("std");
const manifest = @import("build.zig.zon");

pub const name: []const u8 = @tagName(manifest.name) ++ "-zig";
pub const version: []const u8 = manifest.version;

test "manifest" {
    try std.testing.expectEqualStrings("debuginfod-zig", name);
    try std.testing.expectEqualStrings("0.193.0", version);
}
