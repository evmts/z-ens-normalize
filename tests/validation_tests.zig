const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");
const validator = ens_normalize.validator;
const tokenizer = ens_normalize.tokenizer;
const code_points = ens_normalize.code_points;

// Test case structure
const ValidationTestCase = struct {
    name: []const u8,
    input: []const u8,
    expected_error: ?validator.ValidationError = null,
    expected_script: ?[]const u8 = null,
    comment: ?[]const u8 = null,
};

// Empty label tests
const EMPTY_TESTS = [_]ValidationTestCase{
    .{ .name = "empty_string", .input = "", .expected_error = validator.ValidationError.EmptyLabel, .comment = "Empty string" },
    .{ .name = "whitespace", .input = " ", .expected_error = validator.ValidationError.EmptyLabel, .comment = "Whitespace only" },
    .{ .name = "soft_hyphen", .input = "\u{00AD}", .expected_error = validator.ValidationError.EmptyLabel, .comment = "Soft hyphen (ignored)" },
};

// Basic valid tests
const BASIC_VALID_TESTS = [_]ValidationTestCase{
    .{ .name = "simple_ascii", .input = "hello", .expected_script = "ASCII", .comment = "Simple ASCII" },
    .{ .name = "digits", .input = "123", .expected_script = "ASCII", .comment = "Digits" },
    .{ .name = "mixed_ascii", .input = "test123", .expected_script = "ASCII", .comment = "Mixed ASCII" },
    .{ .name = "with_hyphen", .input = "test-name", .expected_script = "ASCII", .comment = "With hyphen" },
};

// Underscore rule tests
const UNDERSCORE_TESTS = [_]ValidationTestCase{
    .{ .name = "leading_underscore", .input = "_hello", .expected_script = "ASCII", .comment = "Leading underscore" },
    .{ .name = "multiple_leading", .input = "____hello", .expected_script = "ASCII", .comment = "Multiple leading underscores" },
    .{ .name = "underscore_middle", .input = "hel_lo", .expected_error = validator.ValidationError.UnderscoreInMiddle, .comment = "Underscore in middle" },
    .{ .name = "underscore_end", .input = "hello_", .expected_error = validator.ValidationError.UnderscoreInMiddle, .comment = "Underscore at end" },
};

// ASCII label extension tests
const LABEL_EXTENSION_TESTS = [_]ValidationTestCase{
    .{ .name = "valid_hyphen", .input = "ab-cd", .expected_script = "ASCII", .comment = "Valid hyphen placement" },
    .{ .name = "invalid_extension", .input = "ab--cd", .expected_error = validator.ValidationError.InvalidLabelExtension, .comment = "Invalid label extension" },
    .{ .name = "xn_extension", .input = "xn--test", .expected_error = validator.ValidationError.InvalidLabelExtension, .comment = "XN label extension" },
};

// Fenced character tests
const FENCED_TESTS = [_]ValidationTestCase{
    .{ .name = "apostrophe_leading", .input = "'hello", .expected_error = validator.ValidationError.FencedLeading, .comment = "Leading apostrophe" },
    .{ .name = "apostrophe_trailing", .input = "hello'", .expected_error = validator.ValidationError.FencedTrailing, .comment = "Trailing apostrophe" },
    .{ .name = "apostrophe_adjacent", .input = "hel''lo", .expected_error = validator.ValidationError.FencedAdjacent, .comment = "Adjacent apostrophes" },
    .{ .name = "apostrophe_valid", .input = "hel'lo", .expected_script = "ASCII", .comment = "Valid apostrophe placement" },
};

// Run test cases
fn runTestCase(test_case: ValidationTestCase) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, test_case.input, &specs, false);
    defer tokenized.deinit();
    
    const result = validator.validateLabel(allocator, tokenized, &specs);
    
    if (test_case.expected_error) |expected_error| {
        try testing.expectError(expected_error, result);
    } else {
        const validated = try result;
        defer validated.deinit();
        
        if (test_case.expected_script) |expected_script| {
            try testing.expectEqualStrings(expected_script, validated.script_group.name);
        }
    }
}

test "validation - empty labels" {
    for (EMPTY_TESTS) |test_case| {
        runTestCase(test_case) catch |err| {
            std.debug.print("Test failed: {s} - {s}\n", .{ test_case.name, test_case.comment orelse "" });
            return err;
        };
    }
}

test "validation - basic valid cases" {
    for (BASIC_VALID_TESTS) |test_case| {
        runTestCase(test_case) catch |err| {
            std.debug.print("Test failed: {s} - {s}\n", .{ test_case.name, test_case.comment orelse "" });
            return err;
        };
    }
}

test "validation - underscore rules" {
    for (UNDERSCORE_TESTS) |test_case| {
        runTestCase(test_case) catch |err| {
            std.debug.print("Test failed: {s} - {s}\n", .{ test_case.name, test_case.comment orelse "" });
            return err;
        };
    }
}

test "validation - label extension rules" {
    for (LABEL_EXTENSION_TESTS) |test_case| {
        runTestCase(test_case) catch |err| {
            std.debug.print("Test failed: {s} - {s}\n", .{ test_case.name, test_case.comment orelse "" });
            return err;
        };
    }
}

test "validation - fenced characters" {
    for (FENCED_TESTS) |test_case| {
        runTestCase(test_case) catch |err| {
            std.debug.print("Test failed: {s} - {s}\n", .{ test_case.name, test_case.comment orelse "" });
            return err;
        };
    }
}

test "validation - script group detection" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // ASCII test
    {
        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello", &specs, false);
        defer tokenized.deinit();
        
        const result = try validator.validateLabel(allocator, tokenized, &specs);
        defer result.deinit();
        
        try testing.expectEqualStrings("ASCII", result.script_group.name);
    }
}

test "validation - performance test" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    const start_time = std.time.microTimestamp();
    
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello", &specs, false);
        defer tokenized.deinit();
        
        const result = try validator.validateLabel(allocator, tokenized, &specs);
        defer result.deinit();
        
        try testing.expectEqualStrings("ASCII", result.script_group.name);
    }
    
    const end_time = std.time.microTimestamp();
    const duration_us = end_time - start_time;
    
    std.debug.print("Validated 1000 times in {d}ms ({d:.2}μs per validation)\n", .{ @divTrunc(duration_us, 1000), @as(f64, @floatFromInt(duration_us)) / 1000.0 });
    
    // Should complete within reasonable time
    try testing.expect(duration_us < 1_000_000); // 1 second
}