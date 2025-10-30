const std = @import("std");

pub fn build(b: *std.Build) void {
    // ============================================================
    // 1. Standard Build Options
    // ============================================================
    // Target configuration (native by default, can be cross-compiled)
    const target = b.standardTargetOptions(.{});

    // Optimization level (Debug, ReleaseSafe, ReleaseFast, ReleaseSmall)
    const optimize = b.standardOptimizeOption(.{});

    // ============================================================
    // 2. Main Module Definition
    // ============================================================
    // Create the main library module that can be imported by other projects
    const mod = b.addModule("z_ens_normalize", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ============================================================
    // 3. Static Library Build (for distribution)
    // ============================================================
    // Build a static library artifact that can be linked into other projects
    const lib = b.addLibrary(.{
        .name = "z_ens_normalize",
        .root_module = mod,
        .linkage = .static,
    });

    // Install the library to zig-out/lib/
    b.installArtifact(lib);

    // ============================================================
    // 4. Test Configuration
    // ============================================================
    // Create test executable that runs all unit tests in the project
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // Create a run step for the tests
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Define the test step that users can run with "zig build test"
    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_mod_tests.step);

    // ============================================================
    // 5. External Test Files (tests/ directory)
    // ============================================================
    // Add external test files that import the main module
    // These tests can access the module via @import("z_ens_normalize")

    // Create test modules
    const ensip15_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/ensip15_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    ensip15_test_mod.addImport("z_ens_normalize", mod);

    const nf_test_mod = b.createModule(.{
        .root_source_file = b.path("tests/nf_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    nf_test_mod.addImport("z_ens_normalize", mod);

    // ENSIP15 normalization tests
    const ensip15_tests = b.addTest(.{
        .root_module = ensip15_test_mod,
    });
    const run_ensip15_tests = b.addRunArtifact(ensip15_tests);
    test_step.dependOn(&run_ensip15_tests.step);

    // NF normalization tests
    const nf_tests = b.addTest(.{
        .root_module = nf_test_mod,
    });
    const run_nf_tests = b.addRunArtifact(nf_tests);
    test_step.dependOn(&run_nf_tests.step);

    // ============================================================
    // 5. Test Data Copy Step
    // ============================================================
    // Create a step to copy test data files (JSON files) to zig-out/test-data/
    // This is useful for tests that need to load external data files
    const copy_test_data = b.step("copy-test-data", "Copy test data files to zig-out/test-data/");

    // Check if test-data directory exists before attempting to copy
    const test_data_dir = "test-data";
    const install_subdir = "test-data";

    // Use installDirectory to copy all files from test-data/ to zig-out/test-data/
    // This will only execute if the source directory exists
    const test_data_exists = checkDirExists(test_data_dir);
    if (test_data_exists) {
        const install_test_data = b.addInstallDirectory(.{
            .source_dir = b.path(test_data_dir),
            .install_dir = .prefix,
            .install_subdir = install_subdir,
        });
        copy_test_data.dependOn(&install_test_data.step);

        // Optionally make tests depend on test data being copied
        // Uncomment the line below if tests require the data files
        // test_step.dependOn(copy_test_data);
    }
}

// ============================================================
// Helper Functions
// ============================================================

/// Check if a directory exists at the given path
fn checkDirExists(path: []const u8) bool {
    var dir = std.fs.cwd().openDir(path, .{}) catch return false;
    dir.close();
    return true;
}
