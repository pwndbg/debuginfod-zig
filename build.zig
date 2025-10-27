const std = @import("std");
const manifest = @import("build.zig.zon");

pub fn generatePkgconfig(b: *std.Build, version: std.SemanticVersion) !*std.Build.Step.InstallFile {
    const allocator = b.allocator;
    const version_str = try std.fmt.allocPrint(allocator, "{d}.{d}", .{version.major, version.minor});
    const absolute_prefix = b.install_prefix;
    if (!std.fs.path.isAbsolute(absolute_prefix)) {
        @panic("Prefix must be absolute!");
    }

    const input_file = try std.fs.cwd().openFile("upstream/libdebuginfod.pc.in", .{});
    defer input_file.close();

    var aw = try std.Io.Writer.Allocating.initCapacity(allocator, 0);
    defer aw.deinit();

    var buf: [0]u8 = undefined;
    var reader = input_file.reader(&buf);
    _ = try reader.interface.stream(&aw.writer, .unlimited);

    var text = try aw.toOwnedSlice();

    // replace @PREFIX@ and @VERSION@
    text = try std.mem.replaceOwned(u8, allocator, text, "@PREFIX@", absolute_prefix);
    text = try std.mem.replaceOwned(u8, allocator, text, "@VERSION@", version_str);

    const tmp_dir = b.makeTempPath();
    const tmp_file = try std.fs.path.join(allocator, &.{tmp_dir, "libdebuginfod.pc"});
    const out_file = try std.fs.cwd().createFile(tmp_file, .{});
    defer out_file.close();
    try out_file.writeAll(text);

    return b.addInstallFile(b.path(tmp_file), "lib/pkgconfig/libdebuginfod.pc");
}

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = try std.SemanticVersion.parse(manifest.version);

    var linkage: std.builtin.LinkMode = .static;
    const linkage_str = b.option(
        []const u8,
        "linkage",
        "linkage type of result library (default: static), options: static,dynamic",
    ) orelse "";
    if (std.mem.eql(u8, linkage_str, "dynamic")) {
        linkage = .dynamic;
    }

    const zon_module = b.createModule(.{
        .root_source_file = b.path("build.zig.zon"),
    });

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/binding.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    lib_mod.addImport("build.zig.zon", zon_module);

    const include = b.addInstallHeaderFile(b.path("upstream/debuginfod.h"), "elfutils/debuginfod.h");
    const pkgconfig = try generatePkgconfig(b, version);
    const lib = b.addLibrary(.{
        .linkage = linkage,
        .name = "debuginfod",
        .root_module = lib_mod,
    });
    if(linkage == .static) {
        lib.bundle_compiler_rt = true;
        lib.pie = true;
    }
    lib.out_filename = "libdebuginfod.so.1";
    lib.setVersionScript(b.path("upstream/libdebuginfod.map"));
    lib.step.dependOn(&include.step);
    lib.step.dependOn(&pkgconfig.step);
    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
