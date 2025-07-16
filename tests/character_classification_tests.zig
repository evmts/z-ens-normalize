const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");
const tokenizer = ens_normalize.tokenizer;
const code_points = ens_normalize.code_points;

// Test case for character classification issues
const CharacterClassificationTest = struct {
    name: []const u8,
    input: []const u8,
    codepoint: u32,
    expected_token_type: tokenizer.TokenType,
    comment: []const u8,
};

// Critical character classification tests
const CLASSIFICATION_TESTS = [_]CharacterClassificationTest{
    // Zero-width characters should be DISALLOWED per ENS specification
    // (Only ZWJ in valid emoji sequences is allowed)
    .{ 
        .name = "zero_width_non_joiner", 
        .input = "\u{200C}", 
        .codepoint = 0x200C,
        .expected_token_type = .disallowed, 
        .comment = "Zero-width non-joiner should be disallowed per ENS spec" 
    },
    .{ 
        .name = "zero_width_joiner", 
        .input = "\u{200D}", 
        .codepoint = 0x200D,
        .expected_token_type = .disallowed, 
        .comment = "Zero-width joiner should be disallowed (except in valid emoji sequences)" 
    },
    .{ 
        .name = "soft_hyphen", 
        .input = "\u{00AD}", 
        .codepoint = 0x00AD,
        .expected_token_type = .ignored, 
        .comment = "Soft hyphen should be ignored" 
    },
    .{ 
        .name = "zero_width_no_break_space", 
        .input = "\u{FEFF}", 
        .codepoint = 0xFEFF,
        .expected_token_type = .ignored, 
        .comment = "Zero-width no-break space should be ignored" 
    },
    
    // Valid characters
    .{ 
        .name = "ascii_lowercase", 
        .input = "a", 
        .codepoint = 'a',
        .expected_token_type = .valid, 
        .comment = "ASCII lowercase should be valid" 
    },
    .{ 
        .name = "ascii_digit", 
        .input = "5", 
        .codepoint = '5',
        .expected_token_type = .valid, 
        .comment = "ASCII digit should be valid" 
    },
    
    // Mapped characters (should use actual spec data, not hardcoded)
    .{ 
        .name = "ascii_uppercase", 
        .input = "A", 
        .codepoint = 'A',
        .expected_token_type = .mapped, 
        .comment = "ASCII uppercase should be mapped to lowercase" 
    },
    
    // Stop character
    .{ 
        .name = "period_stop", 
        .input = ".", 
        .codepoint = '.',
        .expected_token_type = .stop, 
        .comment = "Period should be stop character" 
    },
};

test "character classification - current failures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    std.debug.print("\n=== CHARACTER CLASSIFICATION TEST ===\n", .{});
    
    var failed_tests: usize = 0;
    var total_tests: usize = 0;
    
    for (CLASSIFICATION_TESTS) |test_case| {
        total_tests += 1;
        
        // Tokenize the single character
        const tokenized = tokenizer.TokenizedName.fromInput(allocator, test_case.input, &specs, false) catch |err| {
            std.debug.print("❌ {s}: Failed to tokenize: {}\n", .{ test_case.name, err });
            failed_tests += 1;
            continue;
        };
        defer tokenized.deinit();
        
        if (tokenized.tokens.len == 0) {
            std.debug.print("❌ {s}: No tokens produced\n", .{test_case.name});
            failed_tests += 1;
            continue;
        }
        
        const actual_type = tokenized.tokens[0].type;
        const expected_type = test_case.expected_token_type;
        
        if (actual_type == expected_type) {
            std.debug.print("✅ {s}: {s} -> {s}\n", .{ test_case.name, @tagName(actual_type), test_case.comment });
        } else {
            std.debug.print("❌ {s}: Expected {s}, got {s} - {s}\n", .{ 
                test_case.name, 
                @tagName(expected_type), 
                @tagName(actual_type), 
                test_case.comment 
            });
            failed_tests += 1;
            
            // Show detailed info for debugging
            if (actual_type == .disallowed) {
                std.debug.print("   Codepoint 0x{x} incorrectly marked as disallowed\n", .{test_case.codepoint});
            }
        }
    }
    
    std.debug.print("\n=== RESULTS ===\n", .{});
    std.debug.print("Passed: {}/{}\n", .{ total_tests - failed_tests, total_tests });
    std.debug.print("Failed: {}\n", .{failed_tests});
    
    // All tests should pass now that we understand the correct ENS behavior
    if (failed_tests > 0) {
        std.debug.print("\n❌ UNEXPECTED FAILURES: Character classification doesn't match ENS specification!\n", .{});
        return error.CharacterClassificationFailures;
    }
}

test "zero-width characters should be disallowed - correct ENS behavior" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test zero-width non-joiner (U+200C) - should be disallowed per ENS spec
    const input = "\u{200C}";
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);
    defer tokenized.deinit();
    
    try testing.expect(tokenized.tokens.len > 0);
    
    const token = tokenized.tokens[0];
    
    std.debug.print("Zero-width non-joiner token type: {s}\n", .{@tagName(token.type)});
    if (token.type == .disallowed) {
        std.debug.print("Codepoint 0x{x} correctly marked as disallowed per ENS spec\n", .{token.data.disallowed.cp});
    }
    
    // This should pass - 0x200C should be disallowed, not ignored
    try testing.expectEqual(tokenizer.TokenType.disallowed, token.type);
}