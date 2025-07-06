const std = @import("std");

pub fn build(b: *std.Build) void
{
    // build options
    const do_strip = b.option(
        bool,
        "strip",
        "Strip the executabes"
    ) orelse false;
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // wclient
    const wclient = b.addExecutable(.{
        .name = "wclient",
        .root_source_file = b.path("src/wclient.zig"),
        .target = target,
        .optimize = optimize,
        .strip = do_strip,
    });
    wclient.linkLibC();
	//wclient.linkSystemLibrary("c");
    //wclient.linkSystemLibrary("gdi32");
    //wclient.linkSystemLibrary("user32");
    //wclient.linkSystemLibrary("kernel32");

    wclient.addIncludePath(b.path("../common"));
    wclient.addIncludePath(b.path("../rdpc/include"));
    wclient.addIncludePath(b.path("../svc/include"));
    wclient.addIncludePath(b.path("../cliprdr/include"));
    wclient.addIncludePath(b.path("../rdpsnd/include"));

    wclient.addObjectFile(b.path("../rdpc/zig-out/lib/rdpc.lib"));
    wclient.addObjectFile(b.path("../svc/zig-out/lib/svc.lib"));
    wclient.addObjectFile(b.path("../cliprdr/zig-out/lib/cliprdr.lib"));
    wclient.addObjectFile(b.path("../rdpsnd/zig-out/lib/rdpsnd.lib"));

    //wclient.addLibraryPath(.{.cwd_relative = "../rdpc/zig-out/bin"});
    //wclient.addLibraryPath(.{.cwd_relative = "../svc/zig-out/bin"});
    //wclient.addLibraryPath(.{.cwd_relative = "../cliprdr/zig-out/bin"});
    //wclient.addLibraryPath(.{.cwd_relative = "../rdpsnd/zig-out/bin"});

	wclient.root_module.addImport("hexdump", b.createModule(.{
        .root_source_file = b.path("../common/hexdump.zig"),
    }));
    wclient.root_module.addImport("strings", b.createModule(.{
        .root_source_file = b.path("../common/strings.zig"),
    }));
    wclient.root_module.addImport("log", b.createModule(.{
        .root_source_file = b.path("../common/log.zig"),
    }));
    wclient.root_module.addImport("win32", b.createModule(.{
        .root_source_file = b.path("../zigwin32/win32.zig"),
    }));
    b.installArtifact(wclient);
}
