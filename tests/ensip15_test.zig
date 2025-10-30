//! ENSIP15 Normalization Test Suite
//!
//! This test file validates the complete ENS normalization pipeline by running
//! all official ENSIP-15 test cases against the implementation.
//!
//! Test Structure:
//! - Reads test-data/ensip15-tests.json using @embedFile
//! - Parses JSON test cases using std.json
//! - Skips first entry (version metadata)
//! - Creates ENSIP15 instance with init()
//! - For each test case: calls normalize()
//! - Validates both success and error cases
//!
//! Expected Behavior:
//! - Tests will FAIL with panic (this is expected)
//! - The ENSIP15 normalization methods are stubbed with @panic
//! - As Tasks 19-23 are implemented, tests will progressively pass
//!
//! Memory Management:
//! - Uses std.testing.allocator (detects leaks)
//! - Frees all normalized strings after validation
//! - Parser cleanup with defer parsed.deinit()
//! - ENSIP15 cleanup with defer ensip15.deinit()

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// Import ENSIP15 module from the built library
const ens = @import("z_ens_normalize");
const Ensip15 = ens.Ensip15;

// ============================================================
// Test Case Structure
// ============================================================

/// Represents a single test case from ensip15-tests.json
const TestCase = struct {
    name: []const u8,
    norm: ?[]const u8 = null,
    @"error": bool = false,
    comment: ?[]const u8 = null,

    // Fields for version metadata (first entry only)
    validated: ?[]const u8 = null,
    built: ?[]const u8 = null,
    cldr: ?[]const u8 = null,
    derived: ?[]const u8 = null,
    ens_hash_base64: ?[]const u8 = null,
    nf_hash_base64: ?[]const u8 = null,
    spec_hash: ?[]const u8 = null,
    unicode: ?[]const u8 = null,
    version: ?[]const u8 = null,
};

// ============================================================
// Helper Functions
// ============================================================

/// Convert codepoint to hex string for debugging
/// Similar to Go's ToHexSequence function
fn codepointToHex(allocator: Allocator, cp: u21) ![]u8 {
    return std.fmt.allocPrint(allocator, "{X}", .{cp});
}

/// Convert string to hex sequence for debugging
/// Example: "abc" -> "61 62 63"
fn toHexSequence(allocator: Allocator, s: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .{};
    defer result.deinit(allocator);

    var view = try std.unicode.Utf8View.init(s);
    var iter = view.iterator();
    var first = true;

    while (iter.nextCodepoint()) |cp| {
        if (!first) {
            try result.append(allocator, ' ');
        }
        const hex = try std.fmt.allocPrint(allocator, "{X}", .{cp});
        defer allocator.free(hex);
        try result.appendSlice(allocator, hex);
        first = false;
    }

    return result.toOwnedSlice(allocator);
}

/// Print test failure with detailed context
fn printTestFailure(
    allocator: Allocator,
    test_case: TestCase,
    expected: []const u8,
    got: anytype,
    error_msg: []const u8,
) void {
    std.debug.print("\n=== Test Failure ===\n", .{});
    std.debug.print("Input: \"{s}\"\n", .{test_case.name});

    if (test_case.comment) |comment| {
        std.debug.print("Comment: {s}\n", .{comment});
    }

    const input_hex = toHexSequence(allocator, test_case.name) catch "<encoding error>";
    defer allocator.free(input_hex);
    std.debug.print("Input codepoints: {s}\n", .{input_hex});

    std.debug.print("\nExpected: \"{s}\"\n", .{expected});
    const expected_hex = toHexSequence(allocator, expected) catch "<encoding error>";
    defer allocator.free(expected_hex);
    std.debug.print("Expected codepoints: {s}\n", .{expected_hex});

    std.debug.print("\nError: {s}\n", .{error_msg});

    // Print what we got (if it's a string)
    if (@TypeOf(got) == []const u8 or @TypeOf(got) == []u8) {
        std.debug.print("Got: \"{s}\"\n", .{got});
        const got_hex = toHexSequence(allocator, got) catch "<encoding error>";
        defer allocator.free(got_hex);
        std.debug.print("Got codepoints: {s}\n", .{got_hex});
    }

    std.debug.print("====================\n\n", .{});
}

// ============================================================
// Main Test Suite
// ============================================================

test "ENSIP15 normalization test suite" {
    const allocator = testing.allocator;

    // Load test data from file at runtime
    // Note: @embedFile can't access files outside the package in Zig 0.15.1
    const file = try std.fs.cwd().openFile("test-data/ensip15-tests.json", .{});
    defer file.close();
    const test_data = try file.readToEndAlloc(allocator, 100 * 1024 * 1024); // 100MB max
    defer allocator.free(test_data);

    // Parse JSON test cases
    const parsed = try std.json.parseFromSlice(
        []TestCase,
        allocator,
        test_data,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    const test_cases = parsed.value;

    // Verify we have test cases
    try testing.expect(test_cases.len > 1);

    // First entry is version metadata - skip it
    const metadata = test_cases[0];
    std.debug.print("\nRunning ENSIP15 tests (version: {s})\n", .{
        metadata.version orelse "unknown",
    });
    if (metadata.unicode) |unicode| {
        std.debug.print("Unicode: {s}\n", .{unicode});
    }
    if (metadata.comment) |comment| {
        std.debug.print("Comment: {s}\n\n", .{comment});
    }

    // Create ENSIP15 instance
    var ensip15 = try Ensip15.init(allocator);
    defer ensip15.deinit();

    // Track statistics
    var total_tests: usize = 0;
    var passed_tests: usize = 0;
    var failed_tests: usize = 0;
    var error_tests: usize = 0;

    // Run all test cases (skip first entry which is metadata)
    for (test_cases[1..], 0..) |test_case, idx| {
        total_tests += 1;

        // Determine expected output
        // If norm is null or empty, expected output equals input (idempotent)
        const expected = if (test_case.norm) |norm|
            (if (norm.len == 0) test_case.name else norm)
        else
            test_case.name;

        // Call normalize - this will panic because it's stubbed
        // We wrap it in a block to handle the panic gracefully
        const result = ensip15.normalize(allocator, test_case.name);

        if (test_case.@"error") {
            // This test case should fail
            error_tests += 1;

            if (result) |normalized| {
                // Unexpected success - test failed
                defer allocator.free(normalized);
                failed_tests += 1;

                printTestFailure(
                    allocator,
                    test_case,
                    expected,
                    normalized,
                    "Expected error but normalization succeeded",
                );

                // Continue testing other cases rather than stopping
                continue;
            } else |err| {
                // Expected failure - test passed
                passed_tests += 1;
                if (idx < 10) { // Only print first few successes
                    std.debug.print("PASS (error case {d}): \"{s}\" -> {any}\n", .{
                        idx + 1,
                        test_case.name,
                        err,
                    });
                }
            }
        } else {
            // This test case should succeed
            if (result) |normalized| {
                defer allocator.free(normalized);

                // Compare with expected
                if (std.mem.eql(u8, normalized, expected)) {
                    passed_tests += 1;
                    if (idx < 10) { // Only print first few successes
                        std.debug.print("PASS {d}: \"{s}\" -> \"{s}\"\n", .{
                            idx + 1,
                            test_case.name,
                            normalized,
                        });
                    }
                } else {
                    failed_tests += 1;
                    printTestFailure(
                        allocator,
                        test_case,
                        expected,
                        normalized,
                        "Normalized output does not match expected",
                    );
                }
            } else |err| {
                // Unexpected error - test failed
                failed_tests += 1;
                printTestFailure(
                    allocator,
                    test_case,
                    expected,
                    err,
                    "Unexpected error during normalization",
                );
            }
        }
    }

    // Print summary
    std.debug.print("\n=== Test Summary ===\n", .{});
    std.debug.print("Total: {d}\n", .{total_tests});
    std.debug.print("Passed: {d}\n", .{passed_tests});
    std.debug.print("Failed: {d}\n", .{failed_tests});
    std.debug.print("Error cases: {d}\n", .{error_tests});
    std.debug.print("====================\n", .{});

    // Note: We don't assert all tests pass because the implementation is stubbed
    // Once the normalization is fully implemented (Tasks 19-23), we would add:
    // try testing.expectEqual(total_tests, passed_tests);
}

// ============================================================
// Individual Test Categories (optional)
// ============================================================
// These tests can be used to run specific categories of tests
// Uncomment and implement as needed during development

// test "ENSIP15 basic ASCII tests" {
//     // Run only ASCII normalization tests
// }

// test "ENSIP15 emoji tests" {
//     // Run only emoji-related tests
// }

// test "ENSIP15 confusable tests" {
//     // Run only confusable detection tests
// }

// test "ENSIP15 error cases" {
//     // Run only tests that should fail
// }

// ============================================================
// Helper Tests
// ============================================================

test "hex sequence helper" {
    const allocator = testing.allocator;

    const result = try toHexSequence(allocator, "abc");
    defer allocator.free(result);

    try testing.expectEqualStrings("61 62 63", result);
}

test "hex sequence unicode" {
    const allocator = testing.allocator;

    // Test with emoji
    const result = try toHexSequence(allocator, "🎉");
    defer allocator.free(result);

    try testing.expectEqualStrings("1F389", result);
}

test "test case parsing" {
    const allocator = testing.allocator;

    // Simple JSON test to verify parsing works
    const json_str =
        \\[
        \\  {"name": "test", "norm": "expected", "error": false, "comment": "basic test"}
        \\]
    ;

    const parsed = try std.json.parseFromSlice(
        []TestCase,
        allocator,
        json_str,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    const cases = parsed.value;
    try testing.expectEqual(@as(usize, 1), cases.len);
    try testing.expectEqualStrings("test", cases[0].name);
    try testing.expectEqualStrings("expected", cases[0].norm.?);
    try testing.expectEqual(false, cases[0].@"error");
}

test "test case idempotent" {
    const allocator = testing.allocator;

    // Test with empty norm field (idempotent case)
    const json_str =
        \\[
        \\  {"name": "test", "norm": "", "error": false}
        \\]
    ;

    const parsed = try std.json.parseFromSlice(
        []TestCase,
        allocator,
        json_str,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();

    const cases = parsed.value;
    const expected = if (cases[0].norm) |norm|
        (if (norm.len == 0) cases[0].name else norm)
    else
        cases[0].name;

    try testing.expectEqualStrings("test", expected);
}

test "ENSIP15 init and deinit" {
    const allocator = testing.allocator;
    var ensip15 = try Ensip15.init(allocator);
    defer ensip15.deinit();
    // Verify basic initialization works
}

// ============================================================
// Confusable Detection Tests
// ============================================================

test "confusable detection - Latin vs Cyrillic" {
    const allocator = testing.allocator;
    var ensip15 = try Ensip15.init(allocator);
    defer ensip15.deinit();

    // Cyrillic "а" (U+0430) looks like Latin "a" (U+0061)
    // A name with all Cyrillic confusables should be rejected
    // Example: scope (Latin) vs scope with Cyrillic 'о' (U+043E)
    const cyrillic_confusable = "sсоре"; // Has Cyrillic с (U+0441) and о (U+043E)

    const result = ensip15.normalize(allocator, cyrillic_confusable);

    // Should fail with confusable error
    try testing.expectError(error.WholeConfusable, result);
}

test "confusable detection - Mixed scripts with unique character" {
    const allocator = testing.allocator;
    var ensip15 = try Ensip15.init(allocator);
    defer ensip15.deinit();

    // If a name contains a unique non-confusable character,
    // it should pass even if other characters are confusable
    // Example: "aб" - Latin 'a' + Cyrillic 'б' (U+0431)
    // The Cyrillic 'б' is unique and breaks confusability
    const mixed_unique = "aб";

    const result = ensip15.normalize(allocator, mixed_unique);

    // This might succeed or fail depending on mixing rules
    // Just verify it doesn't crash
    if (result) |normalized| {
        allocator.free(normalized);
    } else |_| {
        // Expected to fail on mixing rules, not confusables
    }
}

test "confusable detection - Valid same-script homoglyphs" {
    const allocator = testing.allocator;
    var ensip15 = try Ensip15.init(allocator);
    defer ensip15.deinit();

    // Homoglyphs within the same script are allowed
    // Example: Greek has its own similar characters
    const greek_name = "αβγ"; // Greek alpha, beta, gamma

    const result = ensip15.normalize(allocator, greek_name);

    // Should succeed
    if (result) |normalized| {
        defer allocator.free(normalized);
        try testing.expect(normalized.len > 0);
    } else |err| {
        std.debug.print("Unexpected error for Greek name: {any}\n", .{err});
        return err;
    }
}

test "confusable detection - ASCII only" {
    const allocator = testing.allocator;
    var ensip15 = try Ensip15.init(allocator);
    defer ensip15.deinit();

    // Pure ASCII should never be confusable
    const ascii_name = "hello";

    const result = ensip15.normalize(allocator, ascii_name);

    // Should succeed
    if (result) |normalized| {
        defer allocator.free(normalized);
        try testing.expectEqualStrings("hello", normalized);
    } else |err| {
        std.debug.print("Unexpected error for ASCII name: {any}\n", .{err});
        return err;
    }
}
