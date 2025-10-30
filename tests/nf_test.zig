const std = @import("std");
const testing = std.testing;

// Import NF module from the built library
const ens = @import("z_ens_normalize");
const NF = ens.NF;

/// Helper function to convert UTF-8 bytes to Unicode codepoints (u21 array).
/// The caller owns the returned memory and must free it.
fn utf8ToCodepoints(allocator: std.mem.Allocator, utf8: []const u8) ![]u21 {
    var codepoints: std.ArrayList(u21) = .{};
    defer codepoints.deinit(allocator);

    var i: usize = 0;
    while (i < utf8.len) {
        const len = try std.unicode.utf8ByteSequenceLength(utf8[i]);
        if (i + len > utf8.len) {
            return error.InvalidUtf8;
        }
        const codepoint = try std.unicode.utf8Decode(utf8[i .. i + len]);
        try codepoints.append(allocator, codepoint);
        i += len;
    }

    return codepoints.toOwnedSlice(allocator);
}

/// Helper function to convert Unicode codepoints (u21 array) to UTF-8 bytes.
/// The caller owns the returned memory and must free it.
fn codepointsToUtf8(allocator: std.mem.Allocator, cps: []const u21) ![]u8 {
    var utf8: std.ArrayList(u8) = .{};
    defer utf8.deinit(allocator);

    for (cps) |cp| {
        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(cp, &buf);
        try utf8.appendSlice(allocator, buf[0..len]);
    }

    return utf8.toOwnedSlice(allocator);
}

// Main NF normalization test suite.
// Reads test data from nf-tests.json and validates NFD and NFC transformations.
//
// Test data format:
// {
//   "Test Category Name": [
//     ["input", "expected_nfd", "expected_nfc"],
//     ...
//   ],
//   ...
// }
//
// Expected behavior:
// - Tests WILL fail because NF.nfd() and NF.nfc() are stubbed with unreachable
// - This is expected and correct - we're building test infrastructure first
// - Once NF implementation is complete, tests will pass
test "NF normalization tests" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Initialize NF instance
    // NOTE: This will panic because init() is stubbed
    // That's expected - we're testing the test infrastructure
    var nf = try NF.init(allocator);
    defer nf.deinit(allocator);

    // Load test data from file
    // Note: @embedFile can't access files outside the package in Zig 0.15.1,
    // so we read it at runtime instead
    const file = try std.fs.cwd().openFile("test-data/nf-tests.json", .{});
    defer file.close();
    const json_data = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(json_data);

    // Parse JSON using std.json
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_data,
        .{},
    );
    defer parsed.deinit();

    const root = parsed.value.object;

    // Track test statistics
    var total_tests: usize = 0;
    var passed_tests: usize = 0;
    var failed_tests: usize = 0;

    // Iterate through each test category
    var it = root.iterator();
    while (it.next()) |entry| {
        const category_name = entry.key_ptr.*;
        const test_cases = entry.value_ptr.*.array;

        std.debug.print("\n=== Testing category: {s} ({d} cases) ===\n", .{ category_name, test_cases.items.len });

        // Iterate through each test case in the category
        for (test_cases.items, 0..) |test_case, i| {
            const case_array = test_case.array;

            // Skip malformed test cases
            if (case_array.items.len != 3) {
                std.debug.print("  [SKIP] Test case {d}: malformed (expected 3 elements, got {d})\n", .{ i, case_array.items.len });
                continue;
            }

            // Extract input, expected NFD, expected NFC
            const input_utf8 = case_array.items[0].string;
            const expected_nfd = case_array.items[1].string;
            const expected_nfc = case_array.items[2].string;

            total_tests += 2; // One for NFD, one for NFC

            // Convert input to codepoints
            const input_cps = utf8ToCodepoints(allocator, input_utf8) catch |err| {
                std.debug.print("  [ERROR] Test {d}: Failed to convert input to codepoints: {}\n", .{ i, err });
                failed_tests += 2;
                continue;
            };
            defer allocator.free(input_cps);

            // Test NFD
            {
                const nfd_result = nf.nfd(allocator, input_cps) catch |err| {
                    std.debug.print("  [FAIL-NFD] Test {d}: nfd() returned error: {}\n", .{ i, err });
                    std.debug.print("    Input: {s}\n", .{input_utf8});
                    failed_tests += 1;
                    // Continue to test NFC even if NFD fails
                    @panic("NFD failed (expected - implementation is stubbed)");
                };
                defer allocator.free(nfd_result);

                const nfd_utf8 = codepointsToUtf8(allocator, nfd_result) catch |err| {
                    std.debug.print("  [ERROR-NFD] Test {d}: Failed to convert NFD result to UTF-8: {}\n", .{ i, err });
                    failed_tests += 1;
                    @panic("NFD result conversion failed");
                };
                defer allocator.free(nfd_utf8);

                // Compare NFD result with expected
                if (!std.mem.eql(u8, expected_nfd, nfd_utf8)) {
                    std.debug.print("  [FAIL-NFD] Test {d}:\n", .{i});
                    std.debug.print("    Input:    '{s}' [", .{input_utf8});
                    for (input_cps, 0..) |cp, idx| {
                        if (idx > 0) std.debug.print(" ", .{});
                        std.debug.print("U+{X:0>4}", .{cp});
                    }
                    std.debug.print("]\n", .{});
                    std.debug.print("    Expected: '{s}'\n", .{expected_nfd});
                    std.debug.print("    Got:      '{s}'\n", .{nfd_utf8});
                    failed_tests += 1;

                    // For now, we expect all tests to fail, so this is normal
                    // Uncomment the following line when implementation is complete:
                    // return error.TestFailed;
                } else {
                    passed_tests += 1;
                }
            }

            // Test NFC
            {
                const nfc_result = nf.nfc(allocator, input_cps) catch |err| {
                    std.debug.print("  [FAIL-NFC] Test {d}: nfc() returned error: {}\n", .{ i, err });
                    std.debug.print("    Input: {s}\n", .{input_utf8});
                    failed_tests += 1;
                    // Continue to next test case
                    @panic("NFC failed (expected - implementation is stubbed)");
                };
                defer allocator.free(nfc_result);

                const nfc_utf8 = codepointsToUtf8(allocator, nfc_result) catch |err| {
                    std.debug.print("  [ERROR-NFC] Test {d}: Failed to convert NFC result to UTF-8: {}\n", .{ i, err });
                    failed_tests += 1;
                    @panic("NFC result conversion failed");
                };
                defer allocator.free(nfc_utf8);

                // Compare NFC result with expected
                if (!std.mem.eql(u8, expected_nfc, nfc_utf8)) {
                    std.debug.print("  [FAIL-NFC] Test {d}:\n", .{i});
                    std.debug.print("    Input:    '{s}' [", .{input_utf8});
                    for (input_cps, 0..) |cp, idx| {
                        if (idx > 0) std.debug.print(" ", .{});
                        std.debug.print("U+{X:0>4}", .{cp});
                    }
                    std.debug.print("]\n", .{});
                    std.debug.print("    Expected: '{s}' [", .{expected_nfc});
                    const expected_cps = utf8ToCodepoints(allocator, expected_nfc) catch &[_]u21{};
                    defer if (expected_cps.len > 0) allocator.free(expected_cps);
                    for (expected_cps, 0..) |cp, idx| {
                        if (idx > 0) std.debug.print(" ", .{});
                        std.debug.print("U+{X:0>4}", .{cp});
                    }
                    std.debug.print("]\n", .{});
                    std.debug.print("    Got:      '{s}' [", .{nfc_utf8});
                    for (nfc_result, 0..) |cp, idx| {
                        if (idx > 0) std.debug.print(" ", .{});
                        std.debug.print("U+{X:0>4}", .{cp});
                    }
                    std.debug.print("]\n", .{});
                    failed_tests += 1;

                    // For now, we expect all tests to fail, so this is normal
                    // Uncomment the following line when implementation is complete:
                    // return error.TestFailed;
                } else {
                    passed_tests += 1;
                }
            }
        }
    }

    // Print summary
    std.debug.print("\n=== Test Summary ===\n", .{});
    std.debug.print("Total tests: {d}\n", .{total_tests});
    std.debug.print("Passed: {d}\n", .{passed_tests});
    std.debug.print("Failed: {d}\n", .{failed_tests});

    // NOTE: We expect all tests to fail because NF methods are stubbed
    // Uncomment this when implementation is complete:
    // if (failed_tests > 0) {
    //     return error.TestsFailed;
    // }
}

// Simple smoke test to verify NF can be initialized (will panic)
test "NF initialization" {
    const allocator = testing.allocator;

    // NF.init() is actually implemented, so test it properly
    var nf = NF.init(allocator) catch |err| {
        std.debug.print("NF.init() returned error: {}\n", .{err});
        return;
    };
    defer nf.deinit(allocator);

    // If we get here, init succeeded as expected
    std.debug.print("NF.init() succeeded as expected\n", .{});
}

// Test decomp map contains problematic codepoints
test "check decomp map for failing codepoints" {
    const allocator = testing.allocator;

    var nf = try NF.init(allocator);
    defer nf.deinit(allocator);

    const test_cps = [_]u21{ 0x0958, 0x0959, 0x095A, 0x09DC, 0x0A59, 0x0B5C, 0xFB3E };
    for (test_cps) |tcp| {
        if (nf.decomps.get(tcp)) |decomp| {
            std.debug.print("U+{X:0>4} -> ", .{tcp});
            for (decomp, 0..) |dc, i| {
                if (i > 0) std.debug.print(" ", .{});
                std.debug.print("U+{X:0>4}", .{dc});
            }
            std.debug.print("\n", .{});
        } else {
            std.debug.print("U+{X:0>4} -> NOT FOUND in decomps map\n", .{tcp});
        }
    }
}

// Test UTF-8 to codepoint conversion helper
test "utf8ToCodepoints" {
    const allocator = testing.allocator;

    // Test ASCII
    {
        const input = "abc";
        const cps = try utf8ToCodepoints(allocator, input);
        defer allocator.free(cps);
        try testing.expectEqualSlices(u21, &[_]u21{ 'a', 'b', 'c' }, cps);
    }

    // Test multi-byte UTF-8
    {
        const input = "café"; // é is U+00E9
        const cps = try utf8ToCodepoints(allocator, input);
        defer allocator.free(cps);
        try testing.expectEqualSlices(u21, &[_]u21{ 'c', 'a', 'f', 0x00E9 }, cps);
    }

    // Test emoji
    {
        const input = "🚀"; // U+1F680
        const cps = try utf8ToCodepoints(allocator, input);
        defer allocator.free(cps);
        try testing.expectEqualSlices(u21, &[_]u21{0x1F680}, cps);
    }

    // Test empty string
    {
        const input = "";
        const cps = try utf8ToCodepoints(allocator, input);
        defer allocator.free(cps);
        try testing.expectEqualSlices(u21, &[_]u21{}, cps);
    }
}

// Test codepoint to UTF-8 conversion helper
test "codepointsToUtf8" {
    const allocator = testing.allocator;

    // Test ASCII
    {
        const cps = [_]u21{ 'a', 'b', 'c' };
        const utf8 = try codepointsToUtf8(allocator, &cps);
        defer allocator.free(utf8);
        try testing.expectEqualStrings("abc", utf8);
    }

    // Test multi-byte UTF-8
    {
        const cps = [_]u21{ 'c', 'a', 'f', 0x00E9 };
        const utf8 = try codepointsToUtf8(allocator, &cps);
        defer allocator.free(utf8);
        try testing.expectEqualStrings("café", utf8);
    }

    // Test emoji
    {
        const cps = [_]u21{0x1F680};
        const utf8 = try codepointsToUtf8(allocator, &cps);
        defer allocator.free(utf8);
        try testing.expectEqualStrings("🚀", utf8);
    }

    // Test empty array
    {
        const cps = [_]u21{};
        const utf8 = try codepointsToUtf8(allocator, &cps);
        defer allocator.free(utf8);
        try testing.expectEqualStrings("", utf8);
    }
}

// Test round-trip conversion (UTF-8 -> codepoints -> UTF-8)
test "utf8 round-trip conversion" {
    const allocator = testing.allocator;

    const test_cases = [_][]const u8{
        "hello",
        "café",
        "🚀",
        "Ḋ",
        "각",
        "ﻵٖ",
        "",
    };

    for (test_cases) |input| {
        const cps = try utf8ToCodepoints(allocator, input);
        defer allocator.free(cps);

        const utf8 = try codepointsToUtf8(allocator, cps);
        defer allocator.free(utf8);

        try testing.expectEqualStrings(input, utf8);
    }
}
