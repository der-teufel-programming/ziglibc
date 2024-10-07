const std = @import("std");
const GitRepoStep = @import("../GitRepoStep.zig");

const BusyboxPrepStep = struct {
    step: std.Build.Step,
    builder: *std.Build,
    repo_path: []const u8,
    pub fn create(b: *std.Build, repo: *GitRepoStep) *BusyboxPrepStep {
        const result = b.allocator.create(BusyboxPrepStep) catch unreachable;
        result.* = BusyboxPrepStep{
            .step = std.Build.Step.init(.{
                .id = .custom,
                .name = "busybox prep",
                .owner = b,
                .makeFn = make,
            }),
            .builder = b,
            .repo_path = repo.path,
        };
        result.*.step.dependOn(&repo.step);
        return result;
    }
    fn make(step: *std.Build.Step, opts: std.Build.Step.MakeOptions) !void {
        _ = opts;
        const self: *BusyboxPrepStep = @fieldParentPtr("step", step);
        const b = self.builder;

        std.log.warn("TODO: check config file timestamp to prevent unnecessary copy", .{});
        // var src_dir = try std.fs.cwd().openDir(b.pathJoin(&.{ b.build_root.path.?, "busybox" }), .{});
        var src_dir = try b.build_root.handle.openDir("busybox", .{});
        defer src_dir.close();
        var dst_dir = try std.fs.cwd().openDir(self.repo_path, .{});
        defer dst_dir.close();
        try src_dir.copyFile("busybox_1_35_0.config", dst_dir, ".config", .{});
    }
};

pub fn add(
    b: *std.Build,
    target: anytype,
    optimize: anytype,
    libc_only_std_static: *std.Build.Step.Compile,
    zig_posix: *std.Build.Step.Compile,
) *std.Build.Step.Compile {
    const repo = GitRepoStep.create(b, .{
        .url = "https://git.busybox.net/busybox",
        .sha = "e512aeb0fb3c585948ae6517cfdf4a53cf99774d",
        .branch = null,
    });

    const prep = BusyboxPrepStep.create(b, repo);

    const exe = b.addExecutable(.{
        .name = "busybox",
        .target = target,
        .optimize = optimize,
    });
    const install = b.addInstallArtifact(exe, .{});
    exe.step.dependOn(&prep.step);
    const repo_path = repo.getPath(&exe.step);
    var files = std.ArrayList([]const u8).init(b.allocator);
    const sources = [_][]const u8{
        "editors/sed.c",
    };
    for (sources) |src| {
        files.append(b.pathJoin(&.{ repo_path, src })) catch unreachable;
    }
    exe.addCSourceFiles(.{
        .files = files.toOwnedSlice() catch unreachable,
        .flags = &[_][]const u8{
            "-std=c99",
        },
    });
    exe.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ repo_path, "include" }) });

    exe.addIncludePath(b.path("inc/libc"));
    exe.addIncludePath(b.path("inc/posix"));
    exe.addIncludePath(b.path("inc/linux"));
    exe.linkLibrary(libc_only_std_static);
    //exe.linkLibrary(zig_start);
    exe.linkLibrary(zig_posix);
    // TODO: should libc_only_std_static and zig_start be able to add library dependencies?
    if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("ntdll");
        exe.linkSystemLibrary("kernel32");
    }

    const step = b.step("busybox", "build busybox and it's applets");
    step.dependOn(&install.step);

    return exe;
}
