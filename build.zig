const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // This creates a "module", which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Every executable or library we compile will be based on one or more modules.
    const lib_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Modules can depend on one another using the `std.Build.Module.addImport` function.
    // This is what allows Zig source code to use `@import("foo")` where 'foo' is not a
    // file path. In this case, we set up `exe_mod` to import `lib_mod`.
    exe_mod.addImport("ens_normalize", lib_mod);

    // Now, we will create a static library based on the module we created above.
    // This creates a `std.Build.Step.Compile`, which is the build step responsible
    // for actually invoking the compiler.
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "ens_normalize",
        .root_module = lib_mod,
    });

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "ens_normalize",
        .root_module = exe_mod,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Add integration tests
    const integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/ens_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_integration_tests = b.addRunArtifact(integration_tests);
    
    // Add tokenization tests
    const tokenization_tests = b.addTest(.{
        .root_source_file = b.path("tests/tokenization_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tokenization_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_tokenization_tests = b.addRunArtifact(tokenization_tests);
    
    // Add tokenization fuzz tests
    const tokenization_fuzz_tests = b.addTest(.{
        .root_source_file = b.path("tests/tokenization_fuzz.zig"),
        .target = target,
        .optimize = optimize,
    });
    tokenization_fuzz_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_tokenization_fuzz_tests = b.addRunArtifact(tokenization_fuzz_tests);
    
    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);
    test_step.dependOn(&run_tokenization_tests.step);
    
    // Add validation tests
    const validation_tests = b.addTest(.{
        .root_source_file = b.path("tests/validation_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    validation_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_validation_tests = b.addRunArtifact(validation_tests);
    
    // Add validation fuzz tests
    const validation_fuzz_tests = b.addTest(.{
        .root_source_file = b.path("tests/validation_fuzz.zig"),
        .target = target,
        .optimize = optimize,
    });
    validation_fuzz_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_validation_fuzz_tests = b.addRunArtifact(validation_fuzz_tests);
    
    // Add separate fuzz test step
    const fuzz_step = b.step("fuzz", "Run fuzz tests");
    fuzz_step.dependOn(&run_tokenization_fuzz_tests.step);
    fuzz_step.dependOn(&run_validation_fuzz_tests.step);
    
    // Add emoji tests
    const emoji_tests = b.addTest(.{
        .root_source_file = b.path("tests/emoji_token_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    emoji_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_emoji_tests = b.addRunArtifact(emoji_tests);
    
    // Add script group tests
    const script_group_tests = b.addTest(.{
        .root_source_file = b.path("tests/script_group_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    script_group_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_script_group_tests = b.addRunArtifact(script_group_tests);
    
    // Add script integration tests
    const script_integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/script_integration_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    script_integration_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_script_integration_tests = b.addRunArtifact(script_integration_tests);
    
    // Add confusable tests
    const confusable_tests = b.addTest(.{
        .root_source_file = b.path("tests/confusable_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    confusable_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_confusable_tests = b.addRunArtifact(confusable_tests);
    
    // Add combining mark tests
    const combining_mark_tests = b.addTest(.{
        .root_source_file = b.path("tests/combining_mark_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    combining_mark_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_combining_mark_tests = b.addRunArtifact(combining_mark_tests);
    
    // Update main test step
    test_step.dependOn(&run_validation_tests.step);
    test_step.dependOn(&run_emoji_tests.step);
    test_step.dependOn(&run_script_group_tests.step);
    test_step.dependOn(&run_script_integration_tests.step);
    test_step.dependOn(&run_confusable_tests.step);
    test_step.dependOn(&run_combining_mark_tests.step);
}
