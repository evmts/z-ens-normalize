const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");
const tokenizer = ens_normalize.tokenizer;
const code_points = ens_normalize.code_points;
const constants = ens_normalize.constants;
const utils = ens_normalize.utils;

// Test case structure based on reference implementations
const TokenizationTestCase = struct {
    name: []const u8,
    input: []const u8,
    expected_tokens: []const ExpectedToken,
    should_error: bool = false,
    comment: ?[]const u8 = null,
};

const ExpectedToken = struct {
    type: tokenizer.TokenType,
    cps: ?[]const u32 = null,
    cp: ?u32 = null,
    input_size: ?usize = null,
};

// Test cases derived from JavaScript implementation
const BASIC_TOKENIZATION_TESTS = [_]TokenizationTestCase{
    .{
        .name = "empty_string",
        .input = "",
        .expected_tokens = &[_]ExpectedToken{},
        .comment = "Empty string should produce no tokens",
    },
    .{
        .name = "simple_ascii",
        .input = "hello",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 'h', 'e', 'l', 'l', 'o' } },
        },
        .comment = "Simple ASCII should collapse into one valid token",
    },
    .{
        .name = "single_character",
        .input = "a",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{'a'} },
        },
        .comment = "Single character should be valid token",
    },
    .{
        .name = "with_stop",
        .input = "hello.eth",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 'h', 'e', 'l', 'l', 'o' } },
            .{ .type = .stop, .cp = constants.CP_STOP },
            .{ .type = .valid, .cps = &[_]u32{ 'e', 't', 'h' } },
        },
        .comment = "Domain with stop character should separate labels",
    },
    .{
        .name = "multiple_stops",
        .input = "a.b.c",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{'a'} },
            .{ .type = .stop, .cp = constants.CP_STOP },
            .{ .type = .valid, .cps = &[_]u32{'b'} },
            .{ .type = .stop, .cp = constants.CP_STOP },
            .{ .type = .valid, .cps = &[_]u32{'c'} },
        },
        .comment = "Multiple stops should separate multiple labels",
    },
    .{
        .name = "with_hyphen",
        .input = "test-domain",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 't', 'e', 's', 't', '-', 'd', 'o', 'm', 'a', 'i', 'n' } },
        },
        .comment = "Hyphen should be valid and collapsed",
    },
    .{
        .name = "mixed_case",
        .input = "Hello",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 'H', 'e', 'l', 'l', 'o' } },
        },
        .comment = "Mixed case should be valid (normalization happens later)",
    },
    .{
        .name = "with_numbers",
        .input = "test123",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 't', 'e', 's', 't', '1', '2', '3' } },
        },
        .comment = "Numbers should be valid",
    },
};

// Test cases for ignored characters (from JavaScript IGNORED set)
const IGNORED_CHARACTERS_TESTS = [_]TokenizationTestCase{
    .{
        .name = "soft_hyphen",
        .input = "test\u{00AD}domain",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 't', 'e', 's', 't' } },
            .{ .type = .ignored, .cp = 0x00AD },
            .{ .type = .valid, .cps = &[_]u32{ 'd', 'o', 'm', 'a', 'i', 'n' } },
        },
        .comment = "Soft hyphen should be ignored",
    },
    .{
        .name = "zero_width_non_joiner",
        .input = "te\u{200C}st",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 't', 'e' } },
            .{ .type = .disallowed, .cp = 0x200C },
            .{ .type = .valid, .cps = &[_]u32{ 's', 't' } },
        },
        .comment = "Zero width non-joiner should be disallowed",
    },
    .{
        .name = "zero_width_joiner_outside_emoji",
        .input = "te\u{200D}st",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 't', 'e' } },
            .{ .type = .disallowed, .cp = 0x200D },
            .{ .type = .valid, .cps = &[_]u32{ 's', 't' } },
        },
        .comment = "Zero width joiner outside emoji should be disallowed",
    },
    .{
        .name = "zero_width_no_break_space",
        .input = "te\u{FEFF}st",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 't', 'e' } },
            .{ .type = .ignored, .cp = 0xFEFF },
            .{ .type = .valid, .cps = &[_]u32{ 's', 't' } },
        },
        .comment = "Zero width no-break space should be ignored",
    },
};

// Test cases for disallowed characters
const DISALLOWED_CHARACTERS_TESTS = [_]TokenizationTestCase{
    .{
        .name = "special_symbols",
        .input = "test!",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 't', 'e', 's', 't' } },
            .{ .type = .disallowed, .cp = '!' },
        },
        .comment = "Special symbols should be disallowed",
    },
    .{
        .name = "at_symbol",
        .input = "user@domain",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 'u', 's', 'e', 'r' } },
            .{ .type = .disallowed, .cp = '@' },
            .{ .type = .valid, .cps = &[_]u32{ 'd', 'o', 'm', 'a', 'i', 'n' } },
        },
        .comment = "At symbol should be disallowed",
    },
    .{
        .name = "hash_symbol",
        .input = "test#hash",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 't', 'e', 's', 't' } },
            .{ .type = .disallowed, .cp = '#' },
            .{ .type = .valid, .cps = &[_]u32{ 'h', 'a', 's', 'h' } },
        },
        .comment = "Hash symbol should be disallowed",
    },
};

// Test cases for edge cases
const EDGE_CASE_TESTS = [_]TokenizationTestCase{
    .{
        .name = "only_stop",
        .input = ".",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .stop, .cp = constants.CP_STOP },
        },
        .comment = "Single stop character",
    },
    .{
        .name = "only_ignored",
        .input = "\u{200C}",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .ignored, .cp = 0x200C },
        },
        .comment = "Single ignored character",
    },
    .{
        .name = "only_disallowed",
        .input = "!",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .disallowed, .cp = '!' },
        },
        .comment = "Single disallowed character",
    },
    .{
        .name = "multiple_consecutive_stops",
        .input = "a..b",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{'a'} },
            .{ .type = .stop, .cp = constants.CP_STOP },
            .{ .type = .stop, .cp = constants.CP_STOP },
            .{ .type = .valid, .cps = &[_]u32{'b'} },
        },
        .comment = "Multiple consecutive stops",
    },
    .{
        .name = "trailing_stop",
        .input = "domain.",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 'd', 'o', 'm', 'a', 'i', 'n' } },
            .{ .type = .stop, .cp = constants.CP_STOP },
        },
        .comment = "Trailing stop character",
    },
    .{
        .name = "leading_stop",
        .input = ".domain",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .stop, .cp = constants.CP_STOP },
            .{ .type = .valid, .cps = &[_]u32{ 'd', 'o', 'm', 'a', 'i', 'n' } },
        },
        .comment = "Leading stop character",
    },
};

// Test cases for NFC normalization (simplified for now)
const NFC_TESTS = [_]TokenizationTestCase{
    .{
        .name = "nfc_simple",
        .input = "test",
        .expected_tokens = &[_]ExpectedToken{
            .{ .type = .valid, .cps = &[_]u32{ 't', 'e', 's', 't' } },
        },
        .comment = "Simple case should not need NFC",
    },
};

// Helper function to run a single test case
fn runTokenizationTest(test_case: TokenizationTestCase) !void {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Tokenize the input
    const result = tokenizer.TokenizedName.fromInput(allocator, test_case.input, &specs, false) catch |err| {
        if (test_case.should_error) {
            return; // Expected error
        }
        std.debug.print("Unexpected error in test '{s}': {}\n", .{ test_case.name, err });
        return err;
    };
    
    if (test_case.should_error) {
        std.debug.print("Test '{s}' should have failed but succeeded\n", .{test_case.name});
        return error.UnexpectedSuccess;
    }
    
    // Check token count
    if (result.tokens.len != test_case.expected_tokens.len) {
        std.debug.print("Test '{s}': expected {} tokens, got {}\n", .{ test_case.name, test_case.expected_tokens.len, result.tokens.len });
        
        // Print actual tokens for debugging
        std.debug.print("Actual tokens:\n", .{});
        for (result.tokens, 0..) |token, i| {
            std.debug.print("  [{}] type={s}", .{ i, @tagName(token.type) });
            switch (token.type) {
                .valid => std.debug.print(" cps={any}", .{token.getCps()}),
                .ignored, .disallowed, .stop => std.debug.print(" cp={}", .{token.getCps()[0]}),
                else => {},
            }
            std.debug.print("\n", .{});
        }
        
        return error.TokenCountMismatch;
    }
    
    // Check each token
    for (result.tokens, test_case.expected_tokens, 0..) |actual, expected, i| {
        if (actual.type != expected.type) {
            std.debug.print("Test '{s}' token {}: expected type {s}, got {s}\n", .{ test_case.name, i, @tagName(expected.type), @tagName(actual.type) });
            return error.TokenTypeMismatch;
        }
        
        switch (expected.type) {
            .valid => {
                if (expected.cps) |expected_cps| {
                    const actual_cps = actual.getCps();
                    if (actual_cps.len != expected_cps.len) {
                        std.debug.print("Test '{s}' token {}: expected {} cps, got {}\n", .{ test_case.name, i, expected_cps.len, actual_cps.len });
                        return error.TokenCpsMismatch;
                    }
                    for (actual_cps, expected_cps) |actual_cp, expected_cp| {
                        if (actual_cp != expected_cp) {
                            std.debug.print("Test '{s}' token {}: expected cp {}, got {}\n", .{ test_case.name, i, expected_cp, actual_cp });
                            return error.TokenCpMismatch;
                        }
                    }
                }
            },
            .ignored, .disallowed, .stop => {
                if (expected.cp) |expected_cp| {
                    const actual_cps = actual.getCps();
                    if (actual_cps.len != 1 or actual_cps[0] != expected_cp) {
                        std.debug.print("Test '{s}' token {}: expected cp {}, got {any}\n", .{ test_case.name, i, expected_cp, actual_cps });
                        return error.TokenCpMismatch;
                    }
                }
            },
            else => {
                // Other token types not fully implemented yet
            },
        }
    }
}

// Individual test functions
test "basic tokenization" {
    for (BASIC_TOKENIZATION_TESTS) |test_case| {
        runTokenizationTest(test_case) catch |err| {
            std.debug.print("Failed basic tokenization test: {s}\n", .{test_case.name});
            return err;
        };
    }
}

test "ignored characters" {
    for (IGNORED_CHARACTERS_TESTS) |test_case| {
        runTokenizationTest(test_case) catch |err| {
            std.debug.print("Failed ignored characters test: {s}\n", .{test_case.name});
            return err;
        };
    }
}

test "disallowed characters" {
    for (DISALLOWED_CHARACTERS_TESTS) |test_case| {
        runTokenizationTest(test_case) catch |err| {
            std.debug.print("Failed disallowed characters test: {s}\n", .{test_case.name});
            return err;
        };
    }
}

test "edge cases" {
    for (EDGE_CASE_TESTS) |test_case| {
        runTokenizationTest(test_case) catch |err| {
            std.debug.print("Failed edge case test: {s}\n", .{test_case.name});
            return err;
        };
    }
}

test "nfc normalization" {
    for (NFC_TESTS) |test_case| {
        runTokenizationTest(test_case) catch |err| {
            std.debug.print("Failed NFC test: {s}\n", .{test_case.name});
            return err;
        };
    }
}

// Performance test
test "tokenization performance" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test with a moderately sized input
    const input = "this-is-a-longer-domain-name-for-performance-testing.eth";
    
    const start = std.time.nanoTimestamp();
    for (0..1000) |_| {
        const result = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);
        _ = result; // Use result to prevent optimization
    }
    const end = std.time.nanoTimestamp();
    
    const duration_ns = end - start;
    const duration_ms = @as(f64, @floatFromInt(duration_ns)) / 1_000_000.0;
    
    std.debug.print("Tokenized 1000 times in {d:.2}ms ({d:.2}μs per tokenization)\n", .{ duration_ms, duration_ms * 1000.0 / 1000.0 });
    
    // Should be reasonably fast
    try testing.expect(duration_ms < 1000.0); // Less than 1 second total
}

// Memory usage test
test "tokenization memory usage" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test that we can tokenize without excessive memory usage
    const inputs = [_][]const u8{
        "short",
        "medium-length-domain.eth",
        "very-long-domain-name-with-many-hyphens-and-characters.subdomain.eth",
        "a.b.c.d.e.f.g.h.i.j.k.l.m.n.o.p.q.r.s.t.u.v.w.x.y.z",
    };
    
    for (inputs) |input| {
        const result = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);
        
        // Basic sanity checks
        try testing.expect(result.tokens.len > 0);
        try testing.expect(result.input.len == input.len);
        
        // Check that we can access all token data without issues
        for (result.tokens) |token| {
            _ = token.getCps();
            _ = token.getInputSize();
            _ = token.isText();
            _ = token.isEmoji();
        }
    }
}

// Integration test with actual ENS names
test "real ens name tokenization" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    const real_names = [_][]const u8{
        "vitalik.eth",
        "ethereum.eth",
        "test-domain.eth",
        "a.eth",
        "subdomain.domain.eth",
        "1234.eth",
        "mixed-Case.eth",
    };
    
    for (real_names) |name| {
        const result = try tokenizer.TokenizedName.fromInput(allocator, name, &specs, false);
        
        // Should have at least one token
        try testing.expect(result.tokens.len > 0);
        
        // Should end with .eth
        try testing.expect(result.tokens[result.tokens.len - 1].type == .valid);
        
        // Should contain a stop character (.)
        var has_stop = false;
        for (result.tokens) |token| {
            if (token.type == .stop) {
                has_stop = true;
                break;
            }
        }
        try testing.expect(has_stop);
    }
}