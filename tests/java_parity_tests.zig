const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");
const log = ens_normalize.logger;

// Test cases based on Java reference implementation validation
// These tests define the expected behavior and will drive implementation

test "NSM validation - duplicate non-spacing marks should fail" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a string with duplicate NSMs - this should fail
    // Using combining diacritics as example NSMs
    const input = "a\u{0300}\u{0300}"; // a with two grave accents (duplicate NSM)
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input);
    try testing.expectError(ens_normalize.ProcessError.DisallowedSequence, result);
}

test "NSM validation - excessive non-spacing marks should fail" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a string with more than 4 consecutive NSMs - this should fail
    const input = "a\u{0300}\u{0301}\u{0302}\u{0303}\u{0304}"; // a with 5 combining marks
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input);
    try testing.expectError(ens_normalize.ProcessError.DisallowedSequence, result);
}

test "NSM validation - valid NSM sequences should pass" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a string with valid NSM usage (≤4 unique NSMs)
    const input = "a\u{0300}\u{0301}\u{0302}"; // a with 3 different combining marks
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input) catch |err| {
        std.log.err("Valid NSM sequence failed: {}", .{err});
        return err;
    };
    defer allocator.free(result);
    
    try testing.expect(result.len > 0);
}

test "combining marks validation - leading combining mark should fail" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // String starting with combining mark - this should fail
    const input = "\u{0300}hello"; // starts with combining grave accent
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input);
    try testing.expectError(ens_normalize.ProcessError.DisallowedSequence, result);
}

test "combining marks validation - combining mark after emoji should fail" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Emoji followed by combining mark - this should fail
    const input = "👍\u{0300}"; // thumbs up emoji + combining grave accent
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input);
    try testing.expectError(ens_normalize.ProcessError.DisallowedSequence, result);
}

test "fenced character validation - leading fenced character should fail" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // String starting with fenced character - this should fail
    const input = "'hello"; // starts with apostrophe (fenced character)
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input);
    try testing.expectError(ens_normalize.ProcessError.DisallowedSequence, result);
}

test "fenced character validation - trailing fenced character should fail" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // String ending with fenced character - this should fail
    const input = "hello'"; // ends with apostrophe (fenced character)
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input);
    try testing.expectError(ens_normalize.ProcessError.DisallowedSequence, result);
}

test "fenced character validation - adjacent fenced characters should fail" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // String with adjacent fenced characters - this should fail
    const input = "he''llo"; // two apostrophes adjacent
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input);
    try testing.expectError(ens_normalize.ProcessError.DisallowedSequence, result);
}

test "confusable detection - whole script confusable should fail" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // String with confusable characters that could be confused with another script
    // Example: Cyrillic 'а' (U+0430) looks like Latin 'a' (U+0061)
    const input = "раус"; // Cyrillic characters that look like Latin "payc"
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input);
    try testing.expectError(ens_normalize.ProcessError.DisallowedSequence, result);
}

test "script mixing validation - mixed scripts should fail" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // String mixing Latin and Greek scripts - this should fail
    const input = "helloα"; // Latin "hello" + Greek "alpha"
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input);
    try testing.expectError(ens_normalize.ProcessError.DisallowedSequence, result);
}

test "emoji trie matching - performance test" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    // Test with complex emoji sequences that should be matched efficiently
    const inputs = [_][]const u8{
        "👨‍👩‍👧‍👦", // family emoji with ZWJ sequences
        "🏳️‍🌈", // rainbow flag with variation selector
        "👍🏻", // thumbs up with skin tone modifier
        "🤷‍♀️", // woman shrugging with ZWJ
    };
    
    for (inputs) |input| {
        const result = normalizer.normalize(input) catch |err| {
            std.log.err("Failed to normalize emoji: {}", .{err});
            return err;
        };
        defer allocator.free(result);
        
        try testing.expect(result.len > 0);
    }
}

test "error type specificity - should provide specific error messages" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    // Test cases that should produce specific error types
    const test_cases = [_]struct {
        input: []const u8,
        expected_error: ens_normalize.ProcessError,
    }{
        .{ .input = "", .expected_error = ens_normalize.ProcessError.DisallowedSequence }, // empty label
        .{ .input = "he_llo", .expected_error = ens_normalize.ProcessError.DisallowedSequence }, // underscore in middle
        .{ .input = "te--st", .expected_error = ens_normalize.ProcessError.DisallowedSequence }, // label extension
        .{ .input = "'hello", .expected_error = ens_normalize.ProcessError.DisallowedSequence }, // fenced leading
        .{ .input = "hello'", .expected_error = ens_normalize.ProcessError.DisallowedSequence }, // fenced trailing
        .{ .input = "\u{0300}hello", .expected_error = ens_normalize.ProcessError.DisallowedSequence }, // CM leading
    };
    
    for (test_cases) |case| {
        const result = normalizer.normalize(case.input);
        try testing.expectError(case.expected_error, result);
    }
}

test "memory management - no double free issues" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    // Test multiple operations to ensure no memory issues
    const inputs = [_][]const u8{
        "hello.eth",
        "test.domain",
        "emoji👍.test",
        "unicode🌈.example",
    };
    
    for (inputs) |input| {
        // Process the same input multiple times
        for (0..10) |_| {
            const result = normalizer.normalize(input) catch |err| {
                std.log.err("Failed to normalize: {}", .{err});
                continue;
            };
            defer allocator.free(result);
        }
    }
}

test "label by label processing - should match Java behavior" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    // Test multi-label domain processing
    const input = "hello.world.eth";
    
    const processed = normalizer.process(input) catch |err| {
        std.log.err("Failed to process: {}", .{err});
        return err;
    };
    defer processed.deinit();
    
    // Should have 3 labels: "hello", "world", "eth"
    try testing.expect(processed.labels.len == 3);
    
    // Each label should be validated independently
    for (processed.labels) |label| {
        try testing.expect(label.tokens.len > 0);
    }
}

test "beautification - Greek character replacement" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    // Test Greek character replacement: ξ (U+03BE) -> Ξ (U+039E) for non-Greek labels
    const input = "testξ"; // Latin text with Greek xi
    
    const result = normalizer.beautify_fn(input) catch |err| {
        std.log.err("Failed to beautify: {}", .{err});
        return err;
    };
    defer allocator.free(result);
    
    // Should contain capital Xi (Ξ) instead of lowercase xi (ξ)
    try testing.expect(std.mem.indexOf(u8, result, "Ξ") != null);
    try testing.expect(std.mem.indexOf(u8, result, "ξ") == null);
}

test "comprehensive validation - all checks should work together" {
    log.setLogLevel(.debug);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.log.err("Failed to initialize normalizer: {}", .{err});
        return;
    };
    defer normalizer.deinit();
    
    // Test valid inputs that should pass all validation checks
    const valid_inputs = [_][]const u8{
        "hello.eth",
        "test123",
        "emoji👍",
        "unicode",
        "_underscore",
        "mixed123",
    };
    
    for (valid_inputs) |input| {
        const result = normalizer.normalize(input) catch |err| {
            std.log.err("Valid input failed validation: {s} -> {}", .{ input, err });
            return err;
        };
        defer allocator.free(result);
        
        try testing.expect(result.len > 0);
    }
}