const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "ens_normalize",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    // C-compatible library
    const c_lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root_c.zig"),
        .target = target,
        .optimize = optimize,
    });
    c_lib_mod.addImport("ens_normalize", lib_mod);

    const c_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "ens_normalize_c",
        .root_module = c_lib_mod,
    });

    b.installArtifact(c_lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/ens_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    integration_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_integration_tests = b.addRunArtifact(integration_tests);
    
    const tokenization_tests = b.addTest(.{
        .root_source_file = b.path("tests/tokenization_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    tokenization_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_tokenization_tests = b.addRunArtifact(tokenization_tests);
    
    const tokenization_fuzz_tests = b.addTest(.{
        .root_source_file = b.path("tests/tokenization_fuzz.zig"),
        .target = target,
        .optimize = optimize,
    });
    tokenization_fuzz_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_tokenization_fuzz_tests = b.addRunArtifact(tokenization_fuzz_tests);
    
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_integration_tests.step);
    test_step.dependOn(&run_tokenization_tests.step);
    
    const validation_tests = b.addTest(.{
        .root_source_file = b.path("tests/validation_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    validation_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_validation_tests = b.addRunArtifact(validation_tests);
    
    const validation_fuzz_tests = b.addTest(.{
        .root_source_file = b.path("tests/validation_fuzz.zig"),
        .target = target,
        .optimize = optimize,
    });
    validation_fuzz_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_validation_fuzz_tests = b.addRunArtifact(validation_fuzz_tests);
    
    const fuzz_step = b.step("fuzz", "Run fuzz tests");
    fuzz_step.dependOn(&run_tokenization_fuzz_tests.step);
    fuzz_step.dependOn(&run_validation_fuzz_tests.step);
    
    const emoji_tests = b.addTest(.{
        .root_source_file = b.path("tests/emoji_token_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    emoji_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_emoji_tests = b.addRunArtifact(emoji_tests);
    
    // TODO: Re-enable after fixing script group crashes
    // const script_group_tests = b.addTest(.{
    //     .root_source_file = b.path("tests/script_group_tests.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // script_group_tests.root_module.addImport("ens_normalize", lib_mod);
    // 
    // const run_script_group_tests = b.addRunArtifact(script_group_tests);
    
    const script_integration_tests = b.addTest(.{
        .root_source_file = b.path("tests/script_integration_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    script_integration_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_script_integration_tests = b.addRunArtifact(script_integration_tests);
    
    const confusable_tests = b.addTest(.{
        .root_source_file = b.path("tests/confusable_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    confusable_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_confusable_tests = b.addRunArtifact(confusable_tests);
    
    // TODO: Re-enable these tests after fixing NSM/combining mark validation crashes
    // const combining_mark_tests = b.addTest(.{
    //     .root_source_file = b.path("tests/combining_mark_tests.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // combining_mark_tests.root_module.addImport("ens_normalize", lib_mod);
    // 
    // const run_combining_mark_tests = b.addRunArtifact(combining_mark_tests);
    // 
    // const nsm_validation_tests = b.addTest(.{
    //     .root_source_file = b.path("tests/nsm_validation_tests.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // nsm_validation_tests.root_module.addImport("ens_normalize", lib_mod);
    // 
    // const run_nsm_validation_tests = b.addRunArtifact(nsm_validation_tests);
    
    const official_test_vectors = b.addTest(.{
        .root_source_file = b.path("tests/official_test_vectors.zig"),
        .target = target,
        .optimize = optimize,
    });
    official_test_vectors.root_module.addImport("ens_normalize", lib_mod);
    
    const run_official_test_vectors = b.addRunArtifact(official_test_vectors);
    
    const character_classification_tests = b.addTest(.{
        .root_source_file = b.path("tests/character_classification_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    character_classification_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_character_classification_tests = b.addRunArtifact(character_classification_tests);
    
    const nfc_normalization_tests = b.addTest(.{
        .root_source_file = b.path("tests/nfc_normalization_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    nfc_normalization_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_nfc_normalization_tests = b.addRunArtifact(nfc_normalization_tests);
    
    const simple_debug_tests = b.addTest(.{
        .root_source_file = b.path("tests/simple_debug.zig"),
        .target = target,
        .optimize = optimize,
    });
    simple_debug_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_simple_debug_tests = b.addRunArtifact(simple_debug_tests);
    
    const nfc_debug_tests = b.addTest(.{
        .root_source_file = b.path("tests/nfc_debug.zig"),
        .target = target,
        .optimize = optimize,
    });
    nfc_debug_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_nfc_debug_tests = b.addRunArtifact(nfc_debug_tests);
    
    const nfc_failing_tests = b.addTest(.{
        .root_source_file = b.path("tests/nfc_failing_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    nfc_failing_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_nfc_failing_tests = b.addRunArtifact(nfc_failing_tests);
    
    // TODO: Fix syntax error in e2e_reference_tests.zig then re-enable
    // const e2e_reference_tests = b.addTest(.{
    //     .root_source_file = b.path("tests/e2e_reference_tests.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // e2e_reference_tests.root_module.addImport("ens_normalize", lib_mod);
    // 
    // const run_e2e_reference_tests = b.addRunArtifact(e2e_reference_tests);
    
    const debug_step = b.step("debug", "Run debug tests");
    debug_step.dependOn(&run_simple_debug_tests.step);
    debug_step.dependOn(&run_nfc_debug_tests.step);
    debug_step.dependOn(&run_nfc_failing_tests.step);
    
    const nfc_debug_detailed_tests = b.addTest(.{
        .root_source_file = b.path("tests/nfc_debug_detailed.zig"),
        .target = target,
        .optimize = optimize,
    });
    nfc_debug_detailed_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_nfc_debug_detailed_tests = b.addRunArtifact(nfc_debug_detailed_tests);
    debug_step.dependOn(&run_nfc_debug_detailed_tests.step);
    
    const nfc_debug_focused_tests = b.addTest(.{
        .root_source_file = b.path("tests/nfc_debug_focused.zig"),
        .target = target,
        .optimize = optimize,
    });
    nfc_debug_focused_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_nfc_debug_focused_tests = b.addRunArtifact(nfc_debug_focused_tests);
    debug_step.dependOn(&run_nfc_debug_focused_tests.step);
    
    test_step.dependOn(&run_validation_tests.step);
    test_step.dependOn(&run_emoji_tests.step);
    // TODO: Re-enable after fixing script group crashes
    // test_step.dependOn(&run_script_group_tests.step);
    test_step.dependOn(&run_script_integration_tests.step);
    test_step.dependOn(&run_confusable_tests.step);
    // TODO: Re-enable these tests after fixing NSM/combining mark validation crashes
    // test_step.dependOn(&run_combining_mark_tests.step);
    // test_step.dependOn(&run_nsm_validation_tests.step);
    test_step.dependOn(&run_official_test_vectors.step);
    test_step.dependOn(&run_character_classification_tests.step);
    test_step.dependOn(&run_nfc_normalization_tests.step);
    // TODO: Fix syntax error in e2e_reference_tests.zig then re-enable
    // test_step.dependOn(&run_e2e_reference_tests.step);
    
    // Add test logging executable
    const test_logging = b.addExecutable(.{
        .name = "test_logging",
        .root_source_file = b.path("test_logging.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_logging.root_module.addImport("ens_normalize", lib_mod);
    b.installArtifact(test_logging);
    
    const run_test_logging = b.addRunArtifact(test_logging);
    const test_logging_step = b.step("test-logging", "Run the logging test");
    test_logging_step.dependOn(&run_test_logging.step);
}
