const std = @import("std");
const testing = std.testing;
const ens = @import("ens_normalize");

test "character mappings - ASCII case folding" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
        comment: []const u8,
    }{
        .{ .input = "HELLO", .expected = "hello", .comment = "Basic uppercase" },
        .{ .input = "Hello", .expected = "hello", .comment = "Mixed case" },
        .{ .input = "HeLLo", .expected = "hello", .comment = "Mixed case complex" },
        .{ .input = "hello", .expected = "hello", .comment = "Already lowercase" },
        .{ .input = "HELLO.ETH", .expected = "hello.eth", .comment = "Domain with uppercase" },
        .{ .input = "Hello.ETH", .expected = "hello.eth", .comment = "Domain mixed case" },
        .{ .input = "TEST.DOMAIN", .expected = "test.domain", .comment = "Multiple labels" },
        .{ .input = "A", .expected = "a", .comment = "Single uppercase" },
        .{ .input = "Z", .expected = "z", .comment = "Last uppercase" },
        .{ .input = "123", .expected = "123", .comment = "Numbers unchanged" },
        .{ .input = "test-123", .expected = "test-123", .comment = "Numbers with hyphens" },
    };
    
    for (test_cases) |case| {
        const result = try ens.normalize(allocator, case.input);
        defer allocator.free(result);
        
        testing.expectEqualStrings(case.expected, result) catch |err| {
            std.debug.print("FAIL: {s} - input: '{s}', expected: '{s}', got: '{s}'\n", .{ case.comment, case.input, case.expected, result });
            return err;
        };
    }
}

test "character mappings - Unicode character mappings" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
        comment: []const u8,
    }{
        // Mathematical symbols
        .{ .input = "ℂ", .expected = "C", .comment = "Complex numbers symbol" },
        .{ .input = "ℌ", .expected = "H", .comment = "Hilbert space symbol" },
        .{ .input = "ℍ", .expected = "H", .comment = "Quaternion symbol" },
        .{ .input = "ℓ", .expected = "l", .comment = "Script small l" },
        
        // Fractions
        .{ .input = "½", .expected = "1⁄2", .comment = "One half" },
        .{ .input = "⅓", .expected = "1⁄3", .comment = "One third" },
        .{ .input = "¼", .expected = "1⁄4", .comment = "One quarter" },
        .{ .input = "¾", .expected = "3⁄4", .comment = "Three quarters" },
        
        // Complex domains
        .{ .input = "test½.eth", .expected = "test1⁄2.eth", .comment = "Domain with fraction" },
        .{ .input = "ℌello.eth", .expected = "Hello.eth", .comment = "Domain with math symbol" },
    };
    
    for (test_cases) |case| {
        const result = try ens.normalize(allocator, case.input);
        defer allocator.free(result);
        
        testing.expectEqualStrings(case.expected, result) catch |err| {
            std.debug.print("FAIL: {s} - input: '{s}', expected: '{s}', got: '{s}'\n", .{ case.comment, case.input, case.expected, result });
            return err;
        };
    }
}

test "character mappings - beautification" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
        comment: []const u8,
    }{
        // ASCII case folding should preserve original case for beautification
        .{ .input = "HELLO", .expected = "HELLO", .comment = "Uppercase preserved" },
        .{ .input = "Hello", .expected = "Hello", .comment = "Mixed case preserved" },
        .{ .input = "hello", .expected = "hello", .comment = "Lowercase preserved" },
        .{ .input = "Hello.ETH", .expected = "Hello.ETH", .comment = "Domain case preserved" },
        
        // Unicode mappings should still apply
        .{ .input = "½", .expected = "1⁄2", .comment = "Fraction still mapped" },
        .{ .input = "ℌ", .expected = "H", .comment = "Math symbol still mapped" },
        .{ .input = "test½.eth", .expected = "test1⁄2.eth", .comment = "Domain with fraction" },
    };
    
    for (test_cases) |case| {
        const result = try ens.beautify(allocator, case.input);
        defer allocator.free(result);
        
        testing.expectEqualStrings(case.expected, result) catch |err| {
            std.debug.print("FAIL: {s} - input: '{s}', expected: '{s}', got: '{s}'\n", .{ case.comment, case.input, case.expected, result });
            return err;
        };
    }
}

test "character mappings - tokenization" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const test_cases = [_]struct {
        input: []const u8,
        expected_types: []const ens.tokenizer.TokenType,
        comment: []const u8,
    }{
        .{ 
            .input = "HELLO", 
            .expected_types = &[_]ens.tokenizer.TokenType{.mapped, .mapped, .mapped, .mapped, .mapped}, 
            .comment = "All uppercase -> mapped" 
        },
        .{ 
            .input = "hello", 
            .expected_types = &[_]ens.tokenizer.TokenType{.valid}, 
            .comment = "All lowercase -> valid (collapsed)" 
        },
        .{ 
            .input = "Hello", 
            .expected_types = &[_]ens.tokenizer.TokenType{.mapped, .valid}, 
            .comment = "Mixed case -> mapped + valid" 
        },
        .{ 
            .input = "½", 
            .expected_types = &[_]ens.tokenizer.TokenType{.mapped}, 
            .comment = "Unicode fraction -> mapped" 
        },
        .{ 
            .input = "test½.eth", 
            .expected_types = &[_]ens.tokenizer.TokenType{.valid, .mapped, .stop, .valid}, 
            .comment = "Domain with fraction" 
        },
    };
    
    for (test_cases) |case| {
        const tokenized = try ens.tokenize(allocator, case.input);
        defer tokenized.deinit();
        
        testing.expectEqual(case.expected_types.len, tokenized.tokens.len) catch |err| {
            std.debug.print("FAIL: {s} - token count mismatch: expected {d}, got {d}\n", .{ case.comment, case.expected_types.len, tokenized.tokens.len });
            return err;
        };
        
        for (case.expected_types, 0..) |expected_type, i| {
            testing.expectEqual(expected_type, tokenized.tokens[i].type) catch |err| {
                std.debug.print("FAIL: {s} - token {d} type mismatch: expected {s}, got {s}\n", .{ case.comment, i, expected_type.toString(), tokenized.tokens[i].type.toString() });
                return err;
            };
        }
    }
}

test "character mappings - ignored characters" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const test_cases = [_]struct {
        input: []const u8,
        expected: []const u8,
        comment: []const u8,
    }{
        .{ .input = "hel\u{00AD}lo", .expected = "hello", .comment = "Soft hyphen ignored" },
        .{ .input = "hel\u{200C}lo", .expected = "hello", .comment = "ZWNJ ignored" },
        .{ .input = "hel\u{200D}lo", .expected = "hello", .comment = "ZWJ ignored" },
        .{ .input = "hel\u{FEFF}lo", .expected = "hello", .comment = "Zero-width no-break space ignored" },
    };
    
    for (test_cases) |case| {
        const result = try ens.normalize(allocator, case.input);
        defer allocator.free(result);
        
        testing.expectEqualStrings(case.expected, result) catch |err| {
            std.debug.print("FAIL: {s} - input: '{s}', expected: '{s}', got: '{s}'\n", .{ case.comment, case.input, case.expected, result });
            return err;
        };
    }
}

test "character mappings - performance test" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const test_inputs = [_][]const u8{
        "HELLO.ETH",
        "Hello.ETH",
        "test½.domain",
        "ℌello.world",
        "MIXED.Case.Domain",
        "with⅓fraction.eth",
        "Complex.ℂ.Domain",
        "Multiple.Labels.With.UPPERCASE",
    };
    
    const iterations = 100;
    var timer = try std.time.Timer.start();
    
    for (0..iterations) |_| {
        for (test_inputs) |input| {
            const result = try ens.normalize(allocator, input);
            defer allocator.free(result);
            
            // Ensure result is valid
            try testing.expect(result.len > 0);
        }
    }
    
    const elapsed = timer.read();
    const ns_per_normalization = elapsed / (iterations * test_inputs.len);
    
    std.debug.print("Character mappings performance: {d} iterations in {d}ns ({d}ns per normalization)\n", .{ iterations * test_inputs.len, elapsed, ns_per_normalization });
    
    // Performance should be reasonable (less than 100μs per normalization)
    try testing.expect(ns_per_normalization < 100_000);
}

test "character mappings - edge cases" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Empty string
    {
        const result = try ens.normalize(allocator, "");
        defer allocator.free(result);
        try testing.expectEqualStrings("", result);
    }
    
    // Single character
    {
        const result = try ens.normalize(allocator, "A");
        defer allocator.free(result);
        try testing.expectEqualStrings("a", result);
    }
    
    // Only periods
    {
        const result = try ens.normalize(allocator, "...");
        defer allocator.free(result);
        try testing.expectEqualStrings("...", result);
    }
    
    // Mixed valid and ignored characters
    {
        const result = try ens.normalize(allocator, "a\u{00AD}b\u{200C}c");
        defer allocator.free(result);
        try testing.expectEqualStrings("abc", result);
    }
}