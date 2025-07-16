const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");

test "NSM validation - should reject more than 4 non-spacing marks" {
    const allocator = testing.allocator;
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    // Test case from C# reference: more than 4 NSMs should fail
    // Using combining diacritical marks (U+0300-U+036F are NSMs)
    // a + 5 combining marks = should fail
    const input = "a\u{0300}\u{0301}\u{0302}\u{0303}\u{0304}";
    
    const result = normalizer.normalize(input);
    try testing.expectError(ens_normalize.ProcessError.DisallowedSequence, result);
}

test "NSM validation - should accept exactly 4 non-spacing marks" {
    const allocator = testing.allocator;
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    // Test case: exactly 4 NSMs should pass
    // a + 4 combining marks = should pass
    const input = "a\u{0300}\u{0301}\u{0302}\u{0303}";
    
    const result = try normalizer.normalize(input);
    defer allocator.free(result);
    
    // Should not throw error and return normalized result
    try testing.expect(result.len > 0);
}

test "NSM validation - should reject duplicate non-spacing marks" {
    const allocator = testing.allocator;
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    // Test case from C# reference: duplicate NSMs should fail
    // a + same combining mark twice = should fail
    const input = "a\u{0300}\u{0300}";
    
    const result = normalizer.normalize(input);
    try testing.expectError(ens_normalize.ProcessError.DisallowedSequence, result);
}

test "NSM validation - should accept different non-spacing marks" {
    const allocator = testing.allocator;
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    // Test case: different NSMs should pass
    // a + 3 different combining marks = should pass
    const input = "a\u{0300}\u{0301}\u{0302}";
    
    const result = try normalizer.normalize(input);
    defer allocator.free(result);
    
    // Should not throw error and return normalized result
    try testing.expect(result.len > 0);
}

test "NSM validation - should check NSMs after NFD decomposition" {
    const allocator = testing.allocator;
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    // Test case: character that decomposes to base + NSM
    // à (U+00E0) decomposes to a (U+0061) + ̀ (U+0300)
    // Adding 4 more NSMs should fail
    const input = "à\u{0301}\u{0302}\u{0303}\u{0304}";
    
    const result = normalizer.normalize(input);
    try testing.expectError(ens_normalize.ProcessError.DisallowedSequence, result);
}

test "NSM validation - should not count NSMs at start of string" {
    const allocator = testing.allocator;
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    // Test case: NSM at start should be rejected for different reason
    // This tests that we don't count leading NSMs in the NSM limit
    const input = "\u{0300}abc";
    
    const result = normalizer.normalize(input);
    try testing.expectError(ens_normalize.ProcessError.DisallowedSequence, result);
}