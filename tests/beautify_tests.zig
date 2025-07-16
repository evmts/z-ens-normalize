const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");

test "beautify: Greek character replacement in non-Greek labels" {
    const allocator = testing.allocator;
    
    // Test cases from ENSIP-15 documentation
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
        description: []const u8,
    }{
        // Basic Greek character replacement
        .{ .input = "ξtest.eth", .expected = "Ξtest.eth", .description = "Replace ξ with Ξ in ASCII label" },
        .{ .input = "testξ.eth", .expected = "testΞ.eth", .description = "Replace ξ with Ξ at end of ASCII label" },
        .{ .input = "teξst.eth", .expected = "teΞst.eth", .description = "Replace ξ with Ξ in middle of ASCII label" },
        
        // Greek labels should NOT have replacement
        .{ .input = "αξβ.eth", .expected = "αξβ.eth", .description = "No replacement in Greek label" },
        .{ .input = "ξενος.eth", .expected = "ξενος.eth", .description = "No replacement in Greek word" },
        
        // Mixed scripts with Greek character
        .{ .input = "ξ123.eth", .expected = "Ξ123.eth", .description = "Replace in numeric label" },
        .{ .input = "ξ💩.eth", .expected = "Ξ💩.eth", .description = "Replace in label with emoji" },
        
        // Multiple labels
        .{ .input = "ξtest.ξeth.eth", .expected = "Ξtest.Ξeth.eth", .description = "Replace in multiple non-Greek labels" },
        .{ .input = "test.αξβ.eth", .expected = "test.αξβ.eth", .description = "Mixed: ASCII and Greek labels" },
        
        // Edge cases
        .{ .input = "ξ.eth", .expected = "Ξ.eth", .description = "Single character label" },
        .{ .input = "ξξξ.eth", .expected = "ΞΞΞ.eth", .description = "Multiple ξ in one label" },
    };
    
    for (test_cases) |tc| {
        const result = try ens_normalize.beautify_fn(allocator, tc.input);
        defer allocator.free(result);
        
        testing.expectEqualStrings(tc.expected, result) catch |err| {
            std.debug.print("FAIL: {s}\n", .{tc.description});
            std.debug.print("  Input:    '{s}'\n", .{tc.input});
            std.debug.print("  Expected: '{s}'\n", .{tc.expected});
            std.debug.print("  Got:      '{s}'\n", .{result});
            return err;
        };
    }
}

test "beautify: Emoji FE0F preservation" {
    const allocator = testing.allocator;
    
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
        description: []const u8,
    }{
        // From ENSIP-15 documentation
        .{ .input = "1️⃣.eth", .expected = "1️⃣.eth", .description = "Preserve FE0F in emoji" },
        .{ .input = "1⃣.eth", .expected = "1️⃣.eth", .description = "Add FE0F to emoji if missing" },
        
        // Multiple emoji
        .{ .input = "1️⃣2️⃣.eth", .expected = "1️⃣2️⃣.eth", .description = "Preserve multiple emoji FE0F" },
        .{ .input = "1⃣2⃣.eth", .expected = "1️⃣2️⃣.eth", .description = "Add FE0F to multiple emoji" },
        
        // Mixed content
        .{ .input = "test1️⃣.eth", .expected = "test1️⃣.eth", .description = "Preserve emoji in mixed content" },
        .{ .input = "🚀️moon.eth", .expected = "🚀️moon.eth", .description = "Preserve emoji at start" },
    };
    
    for (test_cases) |tc| {
        const result = try ens_normalize.beautify_fn(allocator, tc.input);
        defer allocator.free(result);
        
        testing.expectEqualStrings(tc.expected, result) catch |err| {
            std.debug.print("FAIL: {s}\n", .{tc.description});
            std.debug.print("  Input:    '{s}'\n", .{tc.input});
            std.debug.print("  Expected: '{s}'\n", .{tc.expected});
            std.debug.print("  Got:      '{s}'\n", .{result});
            return err;
        };
    }
}

test "beautify: Combined Greek replacement and emoji preservation" {
    const allocator = testing.allocator;
    
    // Test case from ENSIP-15: beautify("-ξ1⃣") → "-Ξ1️⃣"
    const result = try ens_normalize.beautify_fn(allocator, "-ξ1⃣");
    defer allocator.free(result);
    
    try testing.expectEqualStrings("-Ξ1️⃣", result);
}

test "beautify: Edge cases" {
    const allocator = testing.allocator;
    
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
        description: []const u8,
    }{
        // Empty and single character
        .{ .input = "", .expected = "", .description = "Empty string" },
        .{ .input = ".", .expected = ".", .description = "Single dot" },
        .{ .input = "..", .expected = "..", .description = "Multiple dots" },
        
        // Labels with only Greek character
        .{ .input = "ξ", .expected = "Ξ", .description = "Single ξ without TLD" },
        .{ .input = "ξ.", .expected = "Ξ.", .description = "Single ξ with trailing dot" },
        .{ .input = ".ξ", .expected = ".Ξ", .description = "Single ξ with leading dot" },
        
        // Mixed case (normalization should lowercase, then beautify)
        .{ .input = "ΞTest.eth", .expected = "Ξtest.eth", .description = "Already uppercase Ξ" },
        .{ .input = "ΞTEST.ETH", .expected = "Ξtest.eth", .description = "All uppercase" },
    };
    
    for (test_cases) |tc| {
        const result = ens_normalize.beautify_fn(allocator, tc.input) catch |err| {
            // Some edge cases might error, which is expected
            if (tc.input.len == 0 or std.mem.eql(u8, tc.input, ".") or std.mem.eql(u8, tc.input, "..")) {
                continue;
            }
            return err;
        };
        defer allocator.free(result);
        
        testing.expectEqualStrings(tc.expected, result) catch |err| {
            std.debug.print("FAIL: {s}\n", .{tc.description});
            std.debug.print("  Input:    '{s}'\n", .{tc.input});
            std.debug.print("  Expected: '{s}'\n", .{tc.expected});
            std.debug.print("  Got:      '{s}'\n", .{result});
            return err;
        };
    }
}

test "beautify: Real-world examples" {
    const allocator = testing.allocator;
    
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
        description: []const u8,
    }{
        // From JavaScript test cases found
        .{ .input = "Ξvisawallet", .expected = "Ξvisawallet", .description = "Existing capital Ξ preserved" },
        .{ .input = "ξvisawallet", .expected = "Ξvisawallet", .description = "Lowercase ξ replaced" },
        .{ .input = "Ξcoin", .expected = "Ξcoin", .description = "Ethereum-related name" },
        .{ .input = "ξthereal", .expected = "Ξthereal", .description = "Ethereum pun" },
        .{ .input = "wξrd", .expected = "wΞrd", .description = "ξ in middle of word" },
        .{ .input = "ξ008", .expected = "Ξ008", .description = "ξ with numbers" },
    };
    
    for (test_cases) |tc| {
        const result = try ens_normalize.beautify_fn(allocator, tc.input);
        defer allocator.free(result);
        
        testing.expectEqualStrings(tc.expected, result) catch |err| {
            std.debug.print("FAIL: {s}\n", .{tc.description});
            std.debug.print("  Input:    '{s}'\n", .{tc.input});
            std.debug.print("  Expected: '{s}'\n", .{tc.expected});
            std.debug.print("  Got:      '{s}'\n", .{result});
            return err;
        };
    }
}