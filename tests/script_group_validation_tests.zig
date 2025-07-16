const std = @import("std");
const testing = std.testing;
const root = @import("ens_normalize");
const normalizer = root.normalizer;
const validate = root.validate;
const tokenizer = root.tokenizer;
const script_groups = root.script_groups;
const log = @import("ens_normalize").logger;

test "script group validation - pure ASCII should pass" {
    log.setLogLevel(.err); // Reduce noise in tests
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test pure ASCII name (should pass)
    const input = "hello";
    const result = ens.normalize(input);
    
    try testing.expect(result != null);
    if (result) |norm| {
        defer norm.deinit();
        try testing.expect(norm.result.len > 0);
    }
}

test "script group validation - pure Greek should pass" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test pure Greek name (should pass)
    const input = "ελληνικά"; // Greek text
    const result = ens.normalize(input);
    
    try testing.expect(result != null);
    if (result) |norm| {
        defer norm.deinit();
        try testing.expect(norm.result.len > 0);
    }
}

test "script group validation - pure Arabic should pass" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test pure Arabic name (should pass)
    const input = "عربية"; // Arabic text
    const result = ens.normalize(input);
    
    try testing.expect(result != null);
    if (result) |norm| {
        defer norm.deinit();
        try testing.expect(norm.result.len > 0);
    }
}

test "script group validation - pure Cyrillic should pass" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test pure Cyrillic name (should pass)
    const input = "русский"; // Russian text
    const result = ens.normalize(input);
    
    try testing.expect(result != null);
    if (result) |norm| {
        defer norm.deinit();
        try testing.expect(norm.result.len > 0);
    }
}

test "script group validation - pure Hebrew should pass" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test pure Hebrew name (should pass)
    const input = "עברית"; // Hebrew text
    const result = ens.normalize(input);
    
    try testing.expect(result != null);
    if (result) |norm| {
        defer norm.deinit();
        try testing.expect(norm.result.len > 0);
    }
}

test "script group validation - mixed scripts should fail" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test mixed Latin + Greek (should fail)
    const input = "helloελληνικά"; // Mixed Latin and Greek
    const result = ens.normalize(input);
    
    // This should fail due to mixed scripts
    try testing.expect(result == null);
}

test "script group validation - confusable scripts should fail" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test confusable Latin + Cyrillic (should fail)
    const input = "helloрусский"; // Mixed Latin and Cyrillic
    const result = ens.normalize(input);
    
    // This should fail due to confusable scripts
    try testing.expect(result == null);
}

test "script group validation - emoji with single script should pass" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test emoji + ASCII (should pass)
    const input = "hello👍"; // ASCII + emoji
    const result = ens.normalize(input);
    
    try testing.expect(result != null);
    if (result) |norm| {
        defer norm.deinit();
        try testing.expect(norm.result.len > 0);
    }
}

test "script group validation - emoji with mixed scripts should fail" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test emoji + mixed scripts (should fail)
    const input = "hello👍ελληνικά"; // ASCII + emoji + Greek
    const result = ens.normalize(input);
    
    // This should fail due to mixed scripts
    try testing.expect(result == null);
}

test "script group validation - special characters in same script should pass" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test ASCII with common punctuation (should pass)
    const input = "hello-world"; // ASCII with hyphen
    const result = ens.normalize(input);
    
    try testing.expect(result != null);
    if (result) |norm| {
        defer norm.deinit();
        try testing.expect(norm.result.len > 0);
    }
}

test "script group validation - script-specific numbers should pass" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test Arabic with Arabic-Indic digits (should pass)
    const input = "عربية٠١٢٣"; // Arabic text with Arabic-Indic digits
    const result = ens.normalize(input);
    
    try testing.expect(result != null);
    if (result) |norm| {
        defer norm.deinit();
        try testing.expect(norm.result.len > 0);
    }
}

test "script group validation - mixed number systems should fail" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test Arabic with ASCII digits (should fail)
    const input = "عربية0123"; // Arabic text with ASCII digits
    const result = ens.normalize(input);
    
    // This should fail due to mixed number systems
    try testing.expect(result == null);
}

test "script group validation - common script characters should pass" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test with common script characters (should pass)
    const input = "hello'world"; // ASCII with apostrophe (common)
    const result = ens.normalize(input);
    
    try testing.expect(result != null);
    if (result) |norm| {
        defer norm.deinit();
        try testing.expect(norm.result.len > 0);
    }
}

test "script group validation - invisible characters should fail" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test with invisible characters (should fail)
    const input = "hello\u{200B}world"; // ASCII with zero-width space
    const result = ens.normalize(input);
    
    // This should fail due to invisible characters
    try testing.expect(result == null);
}

test "script group validation - Han script should pass" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test Chinese/Japanese/Korean characters (should pass)
    const input = "中文"; // Chinese characters
    const result = ens.normalize(input);
    
    try testing.expect(result != null);
    if (result) |norm| {
        defer norm.deinit();
        try testing.expect(norm.result.len > 0);
    }
}

test "script group validation - mixed Han and Latin should fail" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test mixed Chinese + Latin (should fail)
    const input = "hello中文"; // Mixed Latin and Chinese
    const result = ens.normalize(input);
    
    // This should fail due to mixed scripts
    try testing.expect(result == null);
}

test "script group validation - Devanagari should pass" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test Devanagari script (should pass)
    const input = "देवनागरी"; // Devanagari text
    const result = ens.normalize(input);
    
    try testing.expect(result != null);
    if (result) |norm| {
        defer norm.deinit();
        try testing.expect(norm.result.len > 0);
    }
}

test "script group validation - Thai should pass" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test Thai script (should pass)
    const input = "ไทย"; // Thai text
    const result = ens.normalize(input);
    
    try testing.expect(result != null);
    if (result) |norm| {
        defer norm.deinit();
        try testing.expect(norm.result.len > 0);
    }
}

test "script group validation - mixed Devanagari and Thai should fail" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test mixed Devanagari + Thai (should fail)
    const input = "देवनागरीไทย"; // Mixed Devanagari and Thai
    const result = ens.normalize(input);
    
    // This should fail due to mixed scripts
    try testing.expect(result == null);
}