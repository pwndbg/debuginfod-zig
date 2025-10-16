const std = @import("std");
const builtin = @import("builtin");
const manifest = @import("manifest.zig");

pub const OsRelease = struct {
    version: ?[]const u8 = null,
    id: ?[]const u8 = null,

    pub fn deinit(self: *OsRelease, allocator: std.mem.Allocator) void {
        if(self.id) |val| allocator.free(val);
        if(self.version) |val| allocator.free(val);
        self.* = undefined;
    }
};

fn parseLinuxOsRelease(allocator: std.mem.Allocator, paths: []const []const u8) !OsRelease {
    var output: OsRelease = .{};
    errdefer output.deinit(allocator);

    var file: ?std.fs.File = null;
    for (paths) |path| {
        file = std.fs.cwd().openFile(path, .{}) catch continue;
        break;
    }
    if (file) |f| {
        defer f.close();

        var buf: [1024]u8 = undefined;
        var reader = f.reader(&buf);

        while (true) {
            const line = reader.interface.takeDelimiterExclusive('\n') catch |err| switch (err) {
                std.io.Reader.DelimiterError.EndOfStream => break,
                else => |e| return e,
            };
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            const eq_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;

            const key = trimmed[0..eq_index];
            var value = trimmed[eq_index + 1 ..];
            value = std.mem.trim(u8, value, " \t\r\n\"'");

            if (output.id == null and std.mem.eql(u8, key, "ID")) {
                output.id = try allocator.dupe(u8, value);
            }
            else if (output.version == null and std.mem.eql(u8, key, "VERSION_ID")) {
                output.version = try allocator.dupe(u8, value);
            }

            if (output.id != null and output.version != null) {
                break;
            }
        }
    }
    return output;
}

fn parsePlistLine(reader: *std.Io.Reader, prefix: []const u8, suffix: []const u8) ![]const u8 {
    const line = try reader.takeDelimiterExclusive('\n');
    const line_trimmed = std.mem.trim(u8, line, " \t\r\n");
    if(!(std.mem.startsWith(u8, line_trimmed, prefix) and std.mem.endsWith(u8, line_trimmed, suffix))) {
        return error.LineIsInvalid;
    }
    const value = line_trimmed[(prefix.len) .. (line_trimmed.len - suffix.len)];
    return value;
}

fn parseMacosOsRelease(allocator: std.mem.Allocator, paths: []const []const u8) !OsRelease {
    var output: OsRelease = .{};
    errdefer output.deinit(allocator);

    var file: ?std.fs.File = null;
    for (paths) |path| {
        file = std.fs.cwd().openFile(path, .{}) catch continue;
        break;
    }
    if (file) |f| {
        defer f.close();

        var buf: [1024]u8 = undefined;
        var reader = f.reader(&buf);

        while (true) {
            const key = parsePlistLine(&reader.interface, "<key>", "</key>") catch |err| switch (err) {
                std.io.Reader.DelimiterError.EndOfStream => break,
                error.LineIsInvalid => continue,
                else => |e| return e,
            };
            if (std.mem.eql(u8, key, "ProductVersion")) {
                const value = parsePlistLine(&reader.interface, "<string>", "</string>") catch |err| switch (err) {
                    std.io.Reader.DelimiterError.EndOfStream => break,
                    error.LineIsInvalid => continue,
                    else => |e| return e,
                };
                output.version = try allocator.dupe(u8, value);
            }
            else if (std.mem.eql(u8, key, "ProductBuildVersion")) {
                const value = parsePlistLine(&reader.interface, "<string>", "</string>") catch |err| switch (err) {
                    std.io.Reader.DelimiterError.EndOfStream => break,
                    error.LineIsInvalid => continue,
                    else => |e| return e,
                };
                output.id = try allocator.dupe(u8, value);
            }
        }
    }
    return output;
}

fn getOsRelease(allocator: std.mem.Allocator) !OsRelease {
    switch (builtin.os.tag) {
        .linux => return parseLinuxOsRelease(allocator, &.{ "/etc/os-release", "/usr/lib/os-release"}),
        .macos => return parseMacosOsRelease(allocator, &.{ "/System/Library/CoreServices/SystemVersion.plist"}),
        else => return .{},
    }
}

test "parseLinuxOsRelease parses basic os-release file" {
    const allocator = std.testing.allocator;

    const fake_data =
        \\DOCUMENTATION_URL="https://nixos.org/learn.html"
        \\HOME_URL="https://nixos.org/"
        \\ID=nixos
        \\LOGO="nix-snowflake"
        \\NAME=NixOS
        \\PRETTY_NAME="NixOS 23.11 (Tapir)"
        \\SUPPORT_END="2024-06-30"
        \\SUPPORT_URL="https://nixos.org/community.html"
        \\VERSION="23.11 (Tapir)"
        \\VERSION_CODENAME=tapir
        \\VERSION_ID="23.11"
    ;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &.{tmp_path, "os-release"});
    defer allocator.free(file_path);
    try tmp_dir.dir.writeFile(.{
        .data = fake_data,
        .sub_path = "os-release",
    });

    var out = try parseLinuxOsRelease(allocator, &.{file_path});
    defer out.deinit(allocator);

    try std.testing.expect(out.id != null);
    try std.testing.expect(out.version != null);

    try std.testing.expectEqualStrings("nixos", out.id.?);
    try std.testing.expectEqualStrings("23.11", out.version.?);
}

test "parseMacosOsRelease parses basic os-release file" {
    const allocator = std.testing.allocator;

    const fake_data =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        \\<plist version="1.0">
        \\<dict>
        \\    <key>BuildID</key>
        \\    <string>52E191FB41A9</string>
        \\    <key>ProductBuildVersion</key>
        \\    <string>25A354</string>
        \\    <key>ProductCopyright</key>
        \\    <string>1983-2025 Apple Inc.</string>
        \\    <key>ProductName</key>
        \\    <string>macOS</string>
        \\    <key>ProductUserVisibleVersion</key>
        \\    <string>26.0</string>
        \\    <key>ProductVersion</key>
        \\    <string>26.0</string>
        \\    <key>iOSSupportVersion</key>
        \\    <string>26.0</string>
        \\</dict>
        \\</plist>
    ;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &.{tmp_path, "SystemVersion.plist"});
    defer allocator.free(file_path);
    try tmp_dir.dir.writeFile(.{
        .data = fake_data,
        .sub_path = "SystemVersion.plist",
    });

    var out = try parseMacosOsRelease(allocator, &.{file_path});
    defer out.deinit(allocator);

    try std.testing.expect(out.version != null);
    try std.testing.expectEqualStrings("26.0", out.version.?);
}

pub fn getUserAgent(allocator: std.mem.Allocator) ![]u8 {
    const uts = std.posix.uname();
    var osr = try getOsRelease(allocator);
    defer osr.deinit(allocator);

    return try std.fmt.allocPrint(
        allocator,
        "{s}/{s},{s}/{s},{s}/{s}",
        .{
            manifest.name,
            manifest.version,
            std.mem.sliceTo(&uts.sysname, 0),
            std.mem.sliceTo(&uts.machine, 0),
            osr.id orelse "",
            osr.version orelse "",
        },
    );
}

test "getUserAgent" {
    const allocator = std.testing.allocator;

    const out = try getUserAgent(allocator);
    defer allocator.free(out);

    std.debug.print("out={s}\n", .{out});
}
