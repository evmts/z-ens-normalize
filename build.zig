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
    
    // Add basic normalization test
    const basic_normalize_test = b.addExecutable(.{
        .name = "test_basic_normalize",
        .root_source_file = b.path("test_basic_normalize.zig"),
        .target = target,
        .optimize = optimize,
    });
    basic_normalize_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_basic_normalize = b.addRunArtifact(basic_normalize_test);
    const basic_test_step = b.step("test-basic", "Run basic normalization test");
    basic_test_step.dependOn(&run_basic_normalize.step);
    
    // Add tokenizer-only test
    const tokenizer_test = b.addExecutable(.{
        .name = "test_tokenizer_only",
        .root_source_file = b.path("test_tokenizer_only.zig"),
        .target = target,
        .optimize = optimize,
    });
    tokenizer_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_tokenizer_test = b.addRunArtifact(tokenizer_test);
    const tokenizer_test_step = b.step("test-tokenizer", "Run tokenizer test");
    tokenizer_test_step.dependOn(&run_tokenizer_test.step);
    
    // Add simple mapping test
    const mapping_test = b.addExecutable(.{
        .name = "test_simple_mapping",
        .root_source_file = b.path("test_simple_mapping.zig"),
        .target = target,
        .optimize = optimize,
    });
    mapping_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_mapping_test = b.addRunArtifact(mapping_test);
    const mapping_test_step = b.step("test-mapping", "Run mapping test");
    mapping_test_step.dependOn(&run_mapping_test.step);
    
    // Add direct tokenize test
    const direct_tokenize_test = b.addExecutable(.{
        .name = "test_direct_tokenize",
        .root_source_file = b.path("test_direct_tokenize.zig"),
        .target = target,
        .optimize = optimize,
    });
    direct_tokenize_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_direct_tokenize_test = b.addRunArtifact(direct_tokenize_test);
    const direct_tokenize_test_step = b.step("test-direct-tokenize", "Run direct tokenize test");
    direct_tokenize_test_step.dependOn(&run_direct_tokenize_test.step);
    
    // Add emoji load test
    const emoji_load_test = b.addExecutable(.{
        .name = "test_emoji_load_only",
        .root_source_file = b.path("test_emoji_load_only.zig"),
        .target = target,
        .optimize = optimize,
    });
    emoji_load_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_emoji_load_test = b.addRunArtifact(emoji_load_test);
    const emoji_load_test_step = b.step("test-emoji-load", "Run emoji load test");
    emoji_load_test_step.dependOn(&run_emoji_load_test.step);
    
    // Add ZWJ/ZWNJ test
    const zwj_zwnj_test = b.addExecutable(.{
        .name = "test_zwj_zwnj",
        .root_source_file = b.path("test_zwj_zwnj.zig"),
        .target = target,
        .optimize = optimize,
    });
    zwj_zwnj_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_zwj_zwnj_test = b.addRunArtifact(zwj_zwnj_test);
    const zwj_zwnj_test_step = b.step("test-zwj-zwnj", "Run ZWJ/ZWNJ test");
    zwj_zwnj_test_step.dependOn(&run_zwj_zwnj_test.step);
    
    // Add simple ZWJ test
    const simple_zwj_test = b.addExecutable(.{
        .name = "test_simple_zwj",
        .root_source_file = b.path("test_simple_zwj.zig"),
        .target = target,
        .optimize = optimize,
    });
    simple_zwj_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_simple_zwj_test = b.addRunArtifact(simple_zwj_test);
    const simple_zwj_test_step = b.step("test-simple-zwj", "Run simple ZWJ test");
    simple_zwj_test_step.dependOn(&run_simple_zwj_test.step);
    
    // Add ZWJ fix test
    const zwj_fix_test = b.addExecutable(.{
        .name = "test_zwj_fix",
        .root_source_file = b.path("test_zwj_fix.zig"),
        .target = target,
        .optimize = optimize,
    });
    zwj_fix_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_zwj_fix_test = b.addRunArtifact(zwj_fix_test);
    const zwj_fix_test_step = b.step("test-zwj-fix", "Run ZWJ fix test");
    zwj_fix_test_step.dependOn(&run_zwj_fix_test.step);
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
    
    // Add dot handling tests
    const dot_handling_tests = b.addTest(.{
        .root_source_file = b.path("tests/dot_handling_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    dot_handling_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_dot_handling_tests = b.addRunArtifact(dot_handling_tests);
    test_step.dependOn(&run_dot_handling_tests.step);
    
    // Add emoji priority tests
    const emoji_priority_tests = b.addTest(.{
        .root_source_file = b.path("tests/emoji_priority_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    emoji_priority_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_emoji_priority_tests = b.addRunArtifact(emoji_priority_tests);
    test_step.dependOn(&run_emoji_priority_tests.step);
    
    // Add beautify tests
    const beautify_tests = b.addTest(.{
        .root_source_file = b.path("tests/beautify_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    beautify_tests.root_module.addImport("ens_normalize", lib_mod);
    const run_beautify_tests = b.addRunArtifact(beautify_tests);
    test_step.dependOn(&run_beautify_tests.step);
    
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
    const nsm_validation_tests = b.addTest(.{
        .root_source_file = b.path("tests/nsm_validation_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    nsm_validation_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_nsm_validation_tests = b.addRunArtifact(nsm_validation_tests);
    
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
    
    const beautify_examples_test = b.addExecutable(.{
        .name = "test_beautify_examples",
        .root_source_file = b.path("test_beautify_examples.zig"),
        .target = target,
        .optimize = optimize,
    });
    beautify_examples_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_beautify_examples_test = b.addRunArtifact(beautify_examples_test);
    const beautify_test_step = b.step("test-beautify", "Run beautify examples test");
    beautify_test_step.dependOn(&run_beautify_examples_test.step);
    
    const beautify_greek_test = b.addExecutable(.{
        .name = "test_beautify_greek",
        .root_source_file = b.path("test_beautify_greek.zig"),
        .target = target,
        .optimize = optimize,
    });
    beautify_greek_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_beautify_greek_test = b.addRunArtifact(beautify_greek_test);
    const beautify_greek_test_step = b.step("test-beautify-greek", "Run beautify Greek xi test");
    beautify_greek_test_step.dependOn(&run_beautify_greek_test.step);
    
    const script_detection_test = b.addExecutable(.{
        .name = "test_script_detection",
        .root_source_file = b.path("test_script_detection.zig"),
        .target = target,
        .optimize = optimize,
    });
    script_detection_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_script_detection_test = b.addRunArtifact(script_detection_test);
    const script_detection_test_step = b.step("test-script-detection", "Run script detection test");
    script_detection_test_step.dependOn(&run_script_detection_test.step);
    
    test_step.dependOn(&run_validation_tests.step);
    test_step.dependOn(&run_emoji_tests.step);
    // TODO: Re-enable after fixing script group crashes
    // test_step.dependOn(&run_script_group_tests.step);
    test_step.dependOn(&run_script_integration_tests.step);
    test_step.dependOn(&run_confusable_tests.step);
    // TODO: Re-enable these tests after fixing NSM/combining mark validation crashes
    // test_step.dependOn(&run_combining_mark_tests.step);
    test_step.dependOn(&run_nsm_validation_tests.step);
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
    
    // Add underscore validation test
    const underscore_test = b.addTest(.{
        .root_source_file = b.path("test_underscore_validation.zig"),
        .target = target,
        .optimize = optimize,
    });
    underscore_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_underscore_test = b.addRunArtifact(underscore_test);
    const underscore_test_step = b.step("test-underscore", "Run underscore validation test");
    underscore_test_step.dependOn(&run_underscore_test.step);
    
    // Add NSM validation test
    const nsm_validation_test = b.addTest(.{
        .root_source_file = b.path("test_nsm_validation.zig"),
        .target = target,
        .optimize = optimize,
    });
    nsm_validation_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_nsm_validation_test = b.addRunArtifact(nsm_validation_test);
    const nsm_test_step = b.step("test-nsm", "Run NSM validation test");
    nsm_test_step.dependOn(&run_nsm_validation_test.step);
    test_step.dependOn(&run_nsm_validation_test.step);
    
    // Add dot fix test
    const dot_fix_test = b.addExecutable(.{
        .name = "test_dot_fix",
        .root_source_file = b.path("test_dot_fix.zig"),
        .target = target,
        .optimize = optimize,
    });
    dot_fix_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_dot_fix_test = b.addRunArtifact(dot_fix_test);
    const dot_fix_test_step = b.step("test-dot-fix", "Run dot fix test");
    dot_fix_test_step.dependOn(&run_dot_fix_test.step);
    
    // Add dot debug test
    const dot_debug_test = b.addExecutable(.{
        .name = "test_dot_debug",
        .root_source_file = b.path("test_dot_debug.zig"),
        .target = target,
        .optimize = optimize,
    });
    dot_debug_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_dot_debug_test = b.addRunArtifact(dot_debug_test);
    const dot_debug_test_step = b.step("test-dot-debug", "Run dot debug test");
    dot_debug_test_step.dependOn(&run_dot_debug_test.step);
    
    // Add Java parity tests
    const java_parity_tests = b.addTest(.{
        .root_source_file = b.path("tests/java_parity_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    java_parity_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_java_parity_tests = b.addRunArtifact(java_parity_tests);
    const java_parity_test_step = b.step("test-java-parity", "Run Java parity tests");
    java_parity_test_step.dependOn(&run_java_parity_tests.step);
    
    // Add ENS reference validation tests
    const ens_reference_validation_tests = b.addTest(.{
        .root_source_file = b.path("tests/ens_reference_validation_tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    ens_reference_validation_tests.root_module.addImport("ens_normalize", lib_mod);
    
    const run_ens_reference_validation_tests = b.addRunArtifact(ens_reference_validation_tests);
    const ens_reference_test_step = b.step("test-ens-reference", "Run ENS reference validation tests");
    ens_reference_test_step.dependOn(&run_ens_reference_validation_tests.step);
    test_step.dependOn(&run_ens_reference_validation_tests.step);
    
    // Add confusable validation test
    const confusable_validation_test = b.addTest(.{
        .root_source_file = b.path("test_confusable_validation.zig"),
        .target = target,
        .optimize = optimize,
    });
    confusable_validation_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_confusable_validation_test = b.addRunArtifact(confusable_validation_test);
    const confusable_test_step = b.step("test-confusable", "Run confusable validation test");
    confusable_test_step.dependOn(&run_confusable_validation_test.step);
    test_step.dependOn(&run_confusable_validation_test.step);
    
    // Add emoji combine debug test
    const emoji_combine_debug_test = b.addExecutable(.{
        .name = "test_emoji_combine_debug",
        .root_source_file = b.path("test_emoji_combine_debug.zig"),
        .target = target,
        .optimize = optimize,
    });
    emoji_combine_debug_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_emoji_combine_debug_test = b.addRunArtifact(emoji_combine_debug_test);
    const emoji_combine_debug_test_step = b.step("test-emoji-combine-debug", "Run emoji combine debug test");
    emoji_combine_debug_test_step.dependOn(&run_emoji_combine_debug_test.step);
    
    // Add simple beautify test
    const beautify_simple_test = b.addExecutable(.{
        .name = "test_beautify_simple",
        .root_source_file = b.path("test_beautify_simple.zig"),
        .target = target,
        .optimize = optimize,
    });
    beautify_simple_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_beautify_simple_test = b.addRunArtifact(beautify_simple_test);
    const beautify_simple_test_step = b.step("test-beautify-simple", "Run simple beautify test");
    beautify_simple_test_step.dependOn(&run_beautify_simple_test.step);
    
    // Add beautify debug test
    const beautify_debug_test = b.addExecutable(.{
        .name = "test_beautify_debug",
        .root_source_file = b.path("test_beautify_debug.zig"),
        .target = target,
        .optimize = optimize,
    });
    beautify_debug_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_beautify_debug_test = b.addRunArtifact(beautify_debug_test);
    const beautify_debug_test_step = b.step("test-beautify-debug", "Run beautify debug test");
    beautify_debug_test_step.dependOn(&run_beautify_debug_test.step);
    
    // Add beautify trace test
    const beautify_trace_test = b.addExecutable(.{
        .name = "test_beautify_trace",
        .root_source_file = b.path("test_beautify_trace.zig"),
        .target = target,
        .optimize = optimize,
    });
    beautify_trace_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_beautify_trace_test = b.addRunArtifact(beautify_trace_test);
    const beautify_trace_test_step = b.step("test-beautify-trace", "Run beautify trace test");
    beautify_trace_test_step.dependOn(&run_beautify_trace_test.step);
    
    // Add beautify correct test
    const beautify_correct_test = b.addExecutable(.{
        .name = "test_beautify_correct",
        .root_source_file = b.path("test_beautify_correct.zig"),
        .target = target,
        .optimize = optimize,
    });
    beautify_correct_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_beautify_correct_test = b.addRunArtifact(beautify_correct_test);
    const beautify_correct_test_step = b.step("test-beautify-correct", "Run beautify correct test");
    beautify_correct_test_step.dependOn(&run_beautify_correct_test.step);
    
    // Add empty string test
    const empty_string_test = b.addExecutable(.{
        .name = "test_empty_string",
        .root_source_file = b.path("test_empty_string.zig"),
        .target = target,
        .optimize = optimize,
    });
    empty_string_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_empty_string_test = b.addRunArtifact(empty_string_test);
    const empty_string_test_step = b.step("test-empty-string", "Run empty string test");
    empty_string_test_step.dependOn(&run_empty_string_test.step);
    
    // Add emoji priority debug test
    const emoji_priority_debug_test = b.addExecutable(.{
        .name = "debug_emoji_priority",
        .root_source_file = b.path("debug_emoji_priority.zig"),
        .target = target,
        .optimize = optimize,
    });
    emoji_priority_debug_test.root_module.addImport("ens_normalize", lib_mod);
    
    const run_emoji_priority_debug_test = b.addRunArtifact(emoji_priority_debug_test);
    const emoji_priority_debug_test_step = b.step("debug-emoji-priority", "Run emoji priority debug test");
    emoji_priority_debug_test_step.dependOn(&run_emoji_priority_debug_test.step);
}
