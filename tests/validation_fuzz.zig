const std = @import("std");
const ens_normalize = @import("ens_normalize");
const validator = ens_normalize.validator;
const tokenizer = ens_normalize.tokenizer;
const code_points = ens_normalize.code_points;
const testing = std.testing;

// Main fuzz testing function
pub fn fuzz_validation(input: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Tokenize first (should never crash)
    const tokenized = tokenizer.TokenizedName.fromInput(
        allocator, 
        input, 
        &specs, 
        false
    ) catch |err| switch (err) {
        error.InvalidUtf8 => return,
        error.OutOfMemory => return,
        else => return err,
    };
    defer tokenized.deinit();
    
    // Validation should handle any tokenized input gracefully
    const result = validator.validateLabel(
        allocator,
        tokenized,
        &specs
    ) catch |err| switch (err) {
        error.EmptyLabel => return,
        error.InvalidLabelExtension => return,
        error.UnderscoreInMiddle => return,
        error.LeadingCombiningMark => return,
        error.CombiningMarkAfterEmoji => return,
        error.FencedLeading => return,
        error.FencedTrailing => return,
        error.FencedAdjacent => return,
        error.DisallowedCharacter => return,
        error.IllegalMixture => return,
        error.WholeScriptConfusable => return,
        error.DuplicateNSM => return,
        error.ExcessiveNSM => return,
        error.OutOfMemory => return,
        error.InvalidUtf8 => return,
        else => return err,
    };
    defer result.deinit();
    
    // Validate result invariants
    try validateValidationInvariants(result);
}

fn validateValidationInvariants(result: validator.ValidatedLabel) !void {
    // Basic invariants
    try testing.expect(result.tokens.len > 0); // Should not be empty if validation succeeded
    
    // Script group should be valid
    _ = result.script_group.toString();
    
    // Should have valid script group
    try testing.expect(result.script_group != .Unknown);
}

// Underscore placement fuzzing
test "fuzz_underscore_placement" {
    const test_cases = [_][]const u8{
        "hello",
        "_hello",
        "he_llo",
        "hello_",
        "___hello",
        "hel_lo_world",
        "_",
        "__",
        "___",
    };
    
    for (test_cases) |case| {
        try fuzz_validation(case);
    }
}

// Fenced character fuzzing
test "fuzz_fenced_characters" {
    const fenced_chars = [_][]const u8{ "'", "·", "⁄" };
    const base_strings = [_][]const u8{ "hello", "test", "world" };
    
    for (fenced_chars) |fenced| {
        for (base_strings) |base| {
            // Leading fenced
            {
                const input = std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ fenced, base }) catch return;
                defer testing.allocator.free(input);
                try fuzz_validation(input);
            }
            
            // Trailing fenced
            {
                const input = std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ base, fenced }) catch return;
                defer testing.allocator.free(input);
                try fuzz_validation(input);
            }
            
            // Middle fenced
            {
                const input = std.fmt.allocPrint(testing.allocator, "he{s}llo", .{fenced}) catch return;
                defer testing.allocator.free(input);
                try fuzz_validation(input);
            }
            
            // Adjacent fenced
            {
                const input = std.fmt.allocPrint(testing.allocator, "he{s}{s}llo", .{ fenced, fenced }) catch return;
                defer testing.allocator.free(input);
                try fuzz_validation(input);
            }
        }
    }
}

// Label extension fuzzing
test "fuzz_label_extensions" {
    const test_cases = [_][]const u8{
        "ab--cd",
        "xn--test",
        "test--",
        "--test",
        "te--st",
        "a--b",
        "ab-cd",
        "ab-c-d",
    };
    
    for (test_cases) |case| {
        try fuzz_validation(case);
    }
}

// Length stress testing
test "fuzz_length_stress" {
    const allocator = testing.allocator;
    
    const lengths = [_]usize{ 1, 10, 100, 1000 };
    const patterns = [_][]const u8{ "a", "ab", "abc", "_test", "test_" };
    
    for (lengths) |len| {
        for (patterns) |pattern| {
            const input = try allocator.alloc(u8, len);
            defer allocator.free(input);
            
            var i: usize = 0;
            while (i < len) {
                const remaining = len - i;
                const copy_len = @min(remaining, pattern.len);
                @memcpy(input[i..i + copy_len], pattern[0..copy_len]);
                i += copy_len;
            }
            
            try fuzz_validation(input);
        }
    }
}

// Random input fuzzing
test "fuzz_random_inputs" {
    const allocator = testing.allocator;
    
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();
    
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const len = random.intRangeAtMost(usize, 0, 50);
        const input = try allocator.alloc(u8, len);
        defer allocator.free(input);
        
        // Fill with random ASCII chars
        for (input) |*byte| {
            byte.* = random.intRangeAtMost(u8, 32, 126);
        }
        
        try fuzz_validation(input);
    }
}

// Unicode boundary fuzzing
test "fuzz_unicode_boundaries" {
    const boundary_codepoints = [_]u21{
        0x007F, // ASCII boundary
        0x0080, // Latin-1 start
        0x07FF, // 2-byte UTF-8 boundary
        0x0800, // 3-byte UTF-8 start
        0xD7FF, // Before surrogate range
        0xE000, // After surrogate range
        0xFFFD, // Replacement character
        0x10000, // 4-byte UTF-8 start
        0x10FFFF, // Maximum valid code point
    };
    
    for (boundary_codepoints) |cp| {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &buf) catch continue;
        try fuzz_validation(buf[0..len]);
    }
}

// Script mixing fuzzing
test "fuzz_script_mixing" {
    const script_chars = [_]struct { []const u8, []const u8 }{
        .{ "hello", "ASCII" },
        .{ "café", "Latin" },
        .{ "γεια", "Greek" },
        .{ "привет", "Cyrillic" },
        .{ "مرحبا", "Arabic" },
        .{ "שלום", "Hebrew" },
    };
    
    for (script_chars) |script1| {
        for (script_chars) |script2| {
            if (std.mem.eql(u8, script1[1], script2[1])) continue;
            
            const mixed = std.fmt.allocPrint(testing.allocator, "{s}{s}", .{ script1[0], script2[0] }) catch return;
            defer testing.allocator.free(mixed);
            
            try fuzz_validation(mixed);
        }
    }
}

// Performance fuzzing
test "fuzz_performance" {
    const allocator = testing.allocator;
    
    const performance_patterns = [_]struct {
        pattern: []const u8,
        repeat_count: usize,
    }{
        .{ .pattern = "a", .repeat_count = 1000 },
        .{ .pattern = "_", .repeat_count = 100 },
        .{ .pattern = "'", .repeat_count = 50 },
        .{ .pattern = "ab", .repeat_count = 500 },
        .{ .pattern = "a_", .repeat_count = 200 },
    };
    
    for (performance_patterns) |case| {
        const input = try allocator.alloc(u8, case.pattern.len * case.repeat_count);
        defer allocator.free(input);
        
        var i: usize = 0;
        while (i < case.repeat_count) : (i += 1) {
            const start = i * case.pattern.len;
            const end = start + case.pattern.len;
            @memcpy(input[start..end], case.pattern);
        }
        
        const start_time = std.time.microTimestamp();
        try fuzz_validation(input);
        const end_time = std.time.microTimestamp();
        
        // Should complete within reasonable time
        const duration_us = end_time - start_time;
        try testing.expect(duration_us < 1_000_000); // 1 second max
    }
}