const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("Prescient", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "Prescient",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "Prescient", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    // Registry builder: zig build registry
    const registry_builder = b.addExecutable(.{
        .name = "registry-builder",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build_tools/registry_builder.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const registry_step = b.step("registry", "Regenerate ComponentRegistry and SystemRegistry");
    const run_registry = b.addRunArtifact(registry_builder);
    run_registry.addArg(b.pathFromRoot("."));
    registry_step.dependOn(&run_registry.step);

    // Auto-run registry builder before compiling
    exe.step.dependOn(&run_registry.step);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    mod_tests.step.dependOn(&run_registry.step);

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // =========================================================================
    // Build Tools - Code generators for components, systems, and registries
    // =========================================================================

    // Component generator: zig build component -- MyComponent
    const component_gen = b.addExecutable(.{
        .name = "component-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build_tools/component_generator.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const component_step = b.step("component", "Generate a new component template");
    const run_component_gen = b.addRunArtifact(component_gen);
    run_component_gen.addArg(b.pathFromRoot("."));
    if (b.args) |args| run_component_gen.addArgs(args);
    component_step.dependOn(&run_component_gen.step);

    // System generator: zig build system -- MySystem
    const system_gen = b.addExecutable(.{
        .name = "system-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build_tools/system_generator.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const system_step = b.step("system", "Generate a new system template");
    const run_system_gen = b.addRunArtifact(system_gen);
    run_system_gen.addArg(b.pathFromRoot("."));
    if (b.args) |args| run_system_gen.addArgs(args);
    system_step.dependOn(&run_system_gen.step);

}
