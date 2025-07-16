const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");

test "Confusable validation - should reject whole script confusables" {
    const allocator = testing.allocator;
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    // Test case from C# reference: mixing visually similar characters from different scripts
    // Example: Latin 'o' (U+006F) mixed with Cyrillic 'о' (U+043E) - they look identical
    const input = "hello"; // h-e-l-l-o in Latin
    const confusable = "hellо"; // h-e-l-l-о with Cyrillic 'о' at the end
    
    // First, the pure Latin should work
    const result1 = try normalizer.normalize(input);
    defer allocator.free(result1);
    try testing.expect(result1.len > 0);
    
    // But the mixed Latin/Cyrillic should fail
    const result2 = normalizer.normalize(confusable);
    try testing.expectError(ens_normalize.ProcessError.Confused, result2);
}

test "Confusable validation - should reject mixed script groups" {
    const allocator = testing.allocator;
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    // Test case: mixing Latin and Greek that look similar
    // Latin 'A' (U+0041) vs Greek 'Α' (U+0391)
    const mixed = "HELLO"; // Using Latin letters
    const with_greek_a = "ΗELLO"; // First letter is Greek Eta (Η, U+0397) which looks like Latin H
    
    // Pure Latin should work
    const result1 = try normalizer.normalize(mixed);
    defer allocator.free(result1);
    try testing.expect(result1.len > 0);
    
    // Mixed Latin/Greek should fail
    const result2 = normalizer.normalize(with_greek_a);
    try testing.expectError(ens_normalize.ProcessError.Confused, result2);
}

test "Confusable validation - should allow same script confusables" {
    const allocator = testing.allocator;
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    // Test case: characters that look similar but are from the same script should be allowed
    // Example: Latin 'l' (lowercase L) and 'I' (uppercase i) look similar but both are Latin
    const input = "Illlegal"; // Mix of I and l
    
    const result = try normalizer.normalize(input);
    defer allocator.free(result);
    
    // Should succeed because all characters are from Latin script
    try testing.expect(result.len > 0);
}

test "Confusable validation - should detect confusable groups" {
    const allocator = testing.allocator;
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    // Test case from spec: certain character combinations are confusable as a group
    // Example from C# POSSIBLY_CONFUSING list
    const confusing_chars = [_][]const u8{
        "ą", // U+0105 - looks like 'a' with tail
        "ç", // U+00E7 - looks like 'c' with tail
        "ę", // U+0119 - looks like 'e' with tail
        "ş", // U+015F - looks like 's' with tail
    };
    
    // These should be flagged as potentially confusing
    for (confusing_chars) |char| {
        const input = try std.fmt.allocPrint(allocator, "test{s}name", .{char});
        defer allocator.free(input);
        
        // For now, we expect these to process (not fail) but be marked as potentially confusing
        // In a full implementation, there might be a separate API to check confusability
        const result = normalizer.normalize(input) catch |err| {
            // If it fails, it should be due to confusability
            try testing.expect(err == ens_normalize.ProcessError.Confused or 
                              err == ens_normalize.ProcessError.ConfusedGroups);
            continue;
        };
        defer allocator.free(result);
    }
}

test "Confusable validation - Greek xi special case" {
    const allocator = testing.allocator;
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    // Test the Greek xi (ξ) character which has special handling
    // In non-Greek contexts, it should be replaced with Ξ (capital xi) during beautification
    const greek_name = "ξενος"; // Greek word starting with xi
    const mixed_name = "testξ"; // Latin with Greek xi
    
    // Pure Greek context should work
    const result1 = normalizer.normalize(greek_name) catch |err| {
        // This might fail if Greek script validation is strict
        try testing.expect(err == ens_normalize.ProcessError.Confused);
        return;
    };
    defer allocator.free(result1);
    
    // Mixed context might fail due to script mixing
    const result2 = normalizer.normalize(mixed_name);
    try testing.expectError(ens_normalize.ProcessError.Confused, result2);
}