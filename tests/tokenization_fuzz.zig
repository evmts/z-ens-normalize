const std = @import("std");
const ens_normalize = @import("ens_normalize");
const tokenizer = ens_normalize.tokenizer;
const code_points = ens_normalize.code_points;
const testing = std.testing;

// Main fuzz testing function that should never crash
pub fn fuzz_tokenization(input: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Should never crash, even with malformed input
    const result = tokenizer.TokenizedName.fromInput(
        allocator, 
        input, 
        &specs, 
        false
    ) catch |err| switch (err) {
        error.InvalidUtf8 => return, // Expected for malformed UTF-8
        error.OutOfMemory => return, // Expected for huge inputs
        else => return err, // Unexpected errors should fail the test
    };
    
    defer result.deinit();
    
    // Verify basic invariants hold for all outputs
    try validateTokenInvariants(result.tokens);
}

// Validate that all tokens maintain basic invariants
fn validateTokenInvariants(tokens: []const tokenizer.Token) !void {
    for (tokens) |token| {
        // All tokens should have valid types
        _ = token.type.toString();
        
        // Memory should be properly managed
        switch (token.data) {
            .valid => |v| try testing.expect(v.cps.len > 0),
            .mapped => |m| {
                try testing.expect(m.cps.len > 0);
                // Original codepoint should be different from mapped
                if (m.cps.len == 1) {
                    try testing.expect(m.cp != m.cps[0]);
                }
            },
            .ignored => |i| _ = i.cp, // Any codepoint is valid for ignored
            .disallowed => |d| _ = d.cp, // Any codepoint is valid for disallowed
            .stop => |s| try testing.expect(s.cp == '.'),
            else => {},
        }
    }
}

// Test specific fuzzing scenarios
test "fuzz_utf8_boundary_cases" {
    
    // Test all single bytes (many will be invalid UTF-8)
    var i: u8 = 0;
    while (i < 255) : (i += 1) {
        const input = [_]u8{i};
        try fuzz_tokenization(&input);
    }
    
    // Test invalid UTF-8 sequences
    const invalid_utf8_cases = [_][]const u8{
        &[_]u8{0x80}, // Continuation byte without start
        &[_]u8{0xC0}, // Start byte without continuation
        &[_]u8{0xC0, 0x80}, // Overlong encoding
        &[_]u8{0xE0, 0x80, 0x80}, // Overlong encoding
        &[_]u8{0xF0, 0x80, 0x80, 0x80}, // Overlong encoding
        &[_]u8{0xFF, 0xFF}, // Invalid start bytes
        &[_]u8{0xED, 0xA0, 0x80}, // High surrogate
        &[_]u8{0xED, 0xB0, 0x80}, // Low surrogate
    };
    
    for (invalid_utf8_cases) |case| {
        try fuzz_tokenization(case);
    }
}

test "fuzz_unicode_plane_cases" {
    
    // Test boundary code points from different Unicode planes
    const boundary_codepoints = [_]u21{
        0x007F, // ASCII boundary
        0x0080, // Latin-1 start
        0x07FF, // 2-byte UTF-8 boundary
        0x0800, // 3-byte UTF-8 start
        0xD7FF, // Before surrogate range
        0xE000, // After surrogate range
        0xFFFD, // Replacement character
        0xFFFE, // Non-character
        0xFFFF, // Non-character
        0x10000, // 4-byte UTF-8 start
        0x10FFFF, // Maximum valid code point
    };
    
    for (boundary_codepoints) |cp| {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &buf) catch continue;
        try fuzz_tokenization(buf[0..len]);
    }
}

test "fuzz_emoji_sequences" {
    
    // Test complex emoji sequences that might cause issues
    const emoji_test_cases = [_][]const u8{
        "👨‍👩‍👧‍👦", // Family emoji with ZWJ
        "🏳️‍🌈", // Flag with variation selector and ZWJ
        "👍🏻", // Emoji with skin tone modifier
        "🔥💯", // Multiple emoji
        "a👍b", // Emoji between ASCII
        "..👍..", // Emoji between separators
        "🚀🚀🚀🚀🚀", // Repeated emoji
        "🇺🇸", // Regional indicator sequence
        "©️", // Copyright with variation selector
        "1️⃣", // Keycap sequence
    };
    
    for (emoji_test_cases) |case| {
        try fuzz_tokenization(case);
    }
}

test "fuzz_length_stress_cases" {
    const allocator = testing.allocator;
    
    // Test various length inputs
    const test_lengths = [_]usize{ 0, 1, 10, 100, 1000, 10000 };
    
    for (test_lengths) |len| {
        // Create input of repeated 'a' characters
        const input = try allocator.alloc(u8, len);
        defer allocator.free(input);
        
        @memset(input, 'a');
        try fuzz_tokenization(input);
        
        // Create input of repeated periods
        @memset(input, '.');
        try fuzz_tokenization(input);
        
        // Create input of repeated invalid characters
        @memset(input, 0x80); // Invalid UTF-8 continuation byte
        try fuzz_tokenization(input);
    }
}

test "fuzz_mixed_input_cases" {
    
    // Test inputs that mix different character types rapidly
    const mixed_cases = [_][]const u8{
        "a.b.c.d", // Valid with stops
        "a\u{00AD}b", // Valid with ignored (soft hyphen)
        "a\u{0000}b", // Valid with null character
        "Hello\u{0301}World", // Valid with combining character
        "test@domain.eth", // Valid with disallowed character
        "café.eth", // Composed character
        "cafe\u{0301}.eth", // Decomposed character
        "test\u{200D}ing", // ZWJ between normal chars
        "混合テスト.eth", // Mixed scripts
        "...........", // Many stops
        "aaaaaaaaaa", // Many valid chars
        "\u{00AD}\u{00AD}\u{00AD}", // Many ignored chars
        "🔥🔥🔥🔥🔥", // Many emoji
    };
    
    for (mixed_cases) |case| {
        try fuzz_tokenization(case);
    }
}

test "fuzz_pathological_inputs" {
    
    // Test inputs designed to trigger edge cases
    const pathological_cases = [_][]const u8{
        "", // Empty string
        ".", // Single stop
        "..", // Double stop
        "...", // Triple stop
        "a.", // Valid then stop
        ".a", // Stop then valid
        "a..", // Valid then double stop
        "..a", // Double stop then valid
        "\u{00AD}", // Single ignored character
        "\u{00AD}\u{00AD}", // Multiple ignored characters
        "a\u{00AD}", // Valid then ignored
        "\u{00AD}a", // Ignored then valid
        "\u{FFFD}", // Replacement character
        "\u{FFFE}", // Non-character
        "\u{10FFFF}", // Maximum code point
    };
    
    for (pathological_cases) |case| {
        try fuzz_tokenization(case);
    }
}

test "fuzz_normalization_edge_cases" {
    
    // Test characters that might interact with normalization
    const normalization_cases = [_][]const u8{
        "café", // é (composed)
        "cafe\u{0301}", // é (decomposed)
        "noe\u{0308}l", // ë (decomposed)
        "noël", // ë (composed)
        "A\u{0300}", // À (decomposed)
        "À", // À (composed)
        "\u{1E9B}\u{0323}", // Long s with dot below
        "\u{0FB2}\u{0F80}", // Tibetan characters
        "\u{0F71}\u{0F72}\u{0F74}", // Tibetan vowel signs
    };
    
    for (normalization_cases) |case| {
        try fuzz_tokenization(case);
    }
}

// Performance fuzzing - ensure no algorithmic complexity issues
test "fuzz_performance_cases" {
    const allocator = testing.allocator;
    
    // Test patterns that might cause performance issues
    const performance_cases = [_]struct {
        pattern: []const u8,
        repeat_count: usize,
    }{
        .{ .pattern = "a", .repeat_count = 1000 },
        .{ .pattern = ".", .repeat_count = 1000 },
        .{ .pattern = "\u{00AD}", .repeat_count = 1000 },
        .{ .pattern = "👍", .repeat_count = 100 },
        .{ .pattern = "a.", .repeat_count = 500 },
        .{ .pattern = ".a", .repeat_count = 500 },
        .{ .pattern = "a\u{00AD}", .repeat_count = 500 },
    };
    
    for (performance_cases) |case| {
        const input = try allocator.alloc(u8, case.pattern.len * case.repeat_count);
        defer allocator.free(input);
        
        var i: usize = 0;
        while (i < case.repeat_count) : (i += 1) {
            const start = i * case.pattern.len;
            const end = start + case.pattern.len;
            @memcpy(input[start..end], case.pattern);
        }
        
        const start_time = std.time.microTimestamp();
        try fuzz_tokenization(input);
        const end_time = std.time.microTimestamp();
        
        // Should complete within reasonable time (1 second for 1000 repetitions)
        const duration_us = end_time - start_time;
        try testing.expect(duration_us < 1_000_000);
    }
}

// Random input fuzzing using a simple PRNG
test "fuzz_random_inputs" {
    const allocator = testing.allocator;
    
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    
    // Test various random inputs
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const len = random.intRangeAtMost(usize, 0, 100);
        const input = try allocator.alloc(u8, len);
        defer allocator.free(input);
        
        // Fill with random bytes
        random.bytes(input);
        
        try fuzz_tokenization(input);
    }
}