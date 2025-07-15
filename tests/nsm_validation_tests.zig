const std = @import("std");
const ens = @import("ens_normalize");
const nsm_validation = ens.nsm_validation;
const script_groups = ens.script_groups;
const static_data_loader = ens.static_data_loader;
const validator = ens.validator;
const tokenizer = ens.tokenizer;
const code_points = ens.code_points;

test "NSM validation - basic count limits" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create mock script groups and group
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);
    defer arabic_group.deinit();
    
    // Add some Arabic NSMs to the groups NSM set
    try groups.nsm_set.put(0x064E, {}); // Fatha
    try groups.nsm_set.put(0x064F, {}); // Damma
    try groups.nsm_set.put(0x0650, {}); // Kasra
    try groups.nsm_set.put(0x0651, {}); // Shadda
    try groups.nsm_set.put(0x0652, {}); // Sukun
    
    // Add to script group CM set
    try arabic_group.cm.put(0x064E, {});
    try arabic_group.cm.put(0x064F, {});
    try arabic_group.cm.put(0x0650, {});
    try arabic_group.cm.put(0x0651, {});
    try arabic_group.cm.put(0x0652, {});
    
    // Test valid sequence: base + 3 NSMs
    const valid_seq = [_]u32{0x0628, 0x064E, 0x064F, 0x0650}; // بَُِ
    try nsm_validation.validateNSM(&valid_seq, &groups, &arabic_group, allocator);
    
    // Test invalid sequence: base + 5 NSMs (exceeds limit)
    const invalid_seq = [_]u32{0x0628, 0x064E, 0x064F, 0x0650, 0x0651, 0x0652};
    const result = nsm_validation.validateNSM(&invalid_seq, &groups, &arabic_group, allocator);
    try testing.expectError(nsm_validation.NSMValidationError.ExcessiveNSM, result);
}

test "NSM validation - duplicate detection" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);
    defer arabic_group.deinit();
    
    try groups.nsm_set.put(0x064E, {});
    try arabic_group.cm.put(0x064E, {});
    
    // Test duplicate NSMs
    const duplicate_seq = [_]u32{0x0628, 0x064E, 0x064E}; // ب + fatha + fatha
    const result = nsm_validation.validateNSM(&duplicate_seq, &groups, &arabic_group, allocator);
    try testing.expectError(nsm_validation.NSMValidationError.DuplicateNSM, result);
}

test "NSM validation - leading NSM detection" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);
    defer arabic_group.deinit();
    
    try groups.nsm_set.put(0x064E, {});
    
    // Test leading NSM
    const leading_nsm = [_]u32{0x064E, 0x0628}; // fatha + ب
    const result = nsm_validation.validateNSM(&leading_nsm, &groups, &arabic_group, allocator);
    try testing.expectError(nsm_validation.NSMValidationError.LeadingNSM, result);
}

test "NSM validation - emoji context" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var emoji_group = script_groups.ScriptGroup.init(allocator, "Emoji", 0);
    defer emoji_group.deinit();
    
    try groups.nsm_set.put(0x064E, {});
    try emoji_group.cm.put(0x064E, {});
    
    // Test NSM after emoji
    const emoji_nsm = [_]u32{0x1F600, 0x064E}; // 😀 + fatha
    const result = nsm_validation.validateNSM(&emoji_nsm, &groups, &emoji_group, allocator);
    try testing.expectError(nsm_validation.NSMValidationError.NSMAfterEmoji, result);
}

test "NSM validation - fenced character context" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    try groups.nsm_set.put(0x0300, {}); // Combining grave accent
    try latin_group.cm.put(0x0300, {});
    
    // Test NSM after fenced character (period)
    const fenced_nsm = [_]u32{'.', 0x0300}; // . + grave accent
    const result = nsm_validation.validateNSM(&fenced_nsm, &groups, &latin_group, allocator);
    try testing.expectError(nsm_validation.NSMValidationError.NSMAfterFenced, result);
}

test "NSM detection - comprehensive Unicode ranges" {
    const testing = std.testing;
    
    // Test various NSM ranges
    try testing.expect(nsm_validation.isNSM(0x0300)); // Combining grave accent
    try testing.expect(nsm_validation.isNSM(0x064E)); // Arabic fatha
    try testing.expect(nsm_validation.isNSM(0x05B4)); // Hebrew point hiriq
    try testing.expect(nsm_validation.isNSM(0x093C)); // Devanagari nukta
    try testing.expect(nsm_validation.isNSM(0x0951)); // Devanagari stress sign udatta
    
    // Test non-NSMs
    try testing.expect(!nsm_validation.isNSM('a'));
    try testing.expect(!nsm_validation.isNSM(0x0628)); // Arabic letter beh
    try testing.expect(!nsm_validation.isNSM(0x05D0)); // Hebrew letter alef
}

test "NSM validation - Arabic script-specific rules" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);
    defer arabic_group.deinit();
    
    try groups.nsm_set.put(0x064E, {}); // Fatha
    try groups.nsm_set.put(0x064F, {}); // Damma
    try groups.nsm_set.put(0x0650, {}); // Kasra
    try groups.nsm_set.put(0x0651, {}); // Shadda
    
    try arabic_group.cm.put(0x064E, {});
    try arabic_group.cm.put(0x064F, {});
    try arabic_group.cm.put(0x0650, {});
    try arabic_group.cm.put(0x0651, {});
    
    // Test valid Arabic sequence
    const valid_arabic = [_]u32{0x0628, 0x064E, 0x0651}; // بَّ (beh + fatha + shadda)
    try nsm_validation.validateNSM(&valid_arabic, &groups, &arabic_group, allocator);
    
    // Test invalid: too many Arabic diacritics on one consonant (Arabic limit is 3)
    const invalid_arabic = [_]u32{0x0628, 0x064E, 0x064F, 0x0650, 0x0651}; // بَُِّ
    const result = nsm_validation.validateNSM(&invalid_arabic, &groups, &arabic_group, allocator);
    try testing.expectError(nsm_validation.NSMValidationError.ExcessiveNSM, result);
}

test "NSM validation - Hebrew script-specific rules" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var hebrew_group = script_groups.ScriptGroup.init(allocator, "Hebrew", 0);
    defer hebrew_group.deinit();
    
    try groups.nsm_set.put(0x05B4, {}); // Hebrew point hiriq
    try groups.nsm_set.put(0x05B7, {}); // Hebrew point patah
    try groups.nsm_set.put(0x05B8, {}); // Hebrew point qamats
    
    try hebrew_group.cm.put(0x05B4, {});
    try hebrew_group.cm.put(0x05B7, {});
    try hebrew_group.cm.put(0x05B8, {});
    
    // Test valid Hebrew sequence (Hebrew allows max 2 NSMs)
    const valid_hebrew = [_]u32{0x05D0, 0x05B4, 0x05B7}; // א + hiriq + patah
    try nsm_validation.validateNSM(&valid_hebrew, &groups, &hebrew_group, allocator);
    
    // Test invalid: too many Hebrew points (exceeds Hebrew limit of 2)
    const invalid_hebrew = [_]u32{0x05D0, 0x05B4, 0x05B7, 0x05B8}; // א + 3 points
    const result = nsm_validation.validateNSM(&invalid_hebrew, &groups, &hebrew_group, allocator);
    try testing.expectError(nsm_validation.NSMValidationError.ExcessiveNSM, result);
}

test "NSM validation - Devanagari script-specific rules" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var devanagari_group = script_groups.ScriptGroup.init(allocator, "Devanagari", 0);
    defer devanagari_group.deinit();
    
    try groups.nsm_set.put(0x093C, {}); // Devanagari nukta
    try groups.nsm_set.put(0x0951, {}); // Devanagari stress sign udatta
    
    try devanagari_group.cm.put(0x093C, {});
    try devanagari_group.cm.put(0x0951, {});
    
    // Test valid Devanagari sequence
    const valid_devanagari = [_]u32{0x0915, 0x093C, 0x0951}; // क + nukta + udatta
    try nsm_validation.validateNSM(&valid_devanagari, &groups, &devanagari_group, allocator);
    
    // Test invalid: NSM on wrong base (vowel instead of consonant)
    const invalid_devanagari = [_]u32{0x0905, 0x093C}; // अ (vowel) + nukta
    const result = nsm_validation.validateNSM(&invalid_devanagari, &groups, &devanagari_group, allocator);
    try testing.expectError(nsm_validation.NSMValidationError.InvalidNSMBase, result);
}

test "NSM validation - integration with full validator" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test with a valid Arabic name with NSMs
    // Note: Using individual codepoints since we need NSM sequences
    // In a real scenario, this would come from proper NFD normalization
    
    // For now, test basic ASCII to ensure no regression
    {
        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello", &specs, false);
        defer tokenized.deinit();
        
        const result = validator.validateLabel(allocator, tokenized, &specs);
        if (result) |validated| {
            defer validated.deinit();
            // Should pass - ASCII names don't have NSMs
            try testing.expect(true);
        } else |err| {
            // Should not fail due to NSM errors for ASCII
            try testing.expect(err != validator.ValidationError.ExcessiveNSM);
            try testing.expect(err != validator.ValidationError.DuplicateNSM);
            try testing.expect(err != validator.ValidationError.LeadingNSM);
        }
    }
}

test "NSM validation - multiple base characters" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);
    defer arabic_group.deinit();
    
    try groups.nsm_set.put(0x064E, {}); // Fatha
    try groups.nsm_set.put(0x064F, {}); // Damma
    
    try arabic_group.cm.put(0x064E, {});
    try arabic_group.cm.put(0x064F, {});
    
    // Test sequence with multiple base characters and their NSMs
    const multi_base = [_]u32{
        0x0628, 0x064E,        // بَ (beh + fatha)
        0x062A, 0x064F,        // تُ (teh + damma)  
        0x062B, 0x064E, 0x064F // ثَُ (theh + fatha + damma)
    };
    
    try nsm_validation.validateNSM(&multi_base, &groups, &arabic_group, allocator);
}

test "NSM validation - empty input" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    const empty_input = [_]u32{};
    try nsm_validation.validateNSM(&empty_input, &groups, &latin_group, allocator);
    // Should pass - empty input is valid
}

test "NSM validation - no NSMs present" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    const no_nsms = [_]u32{'h', 'e', 'l', 'l', 'o'};
    try nsm_validation.validateNSM(&no_nsms, &groups, &latin_group, allocator);
    // Should pass - no NSMs to validate
}

test "NSM validation - performance test" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);
    defer arabic_group.deinit();
    
    try groups.nsm_set.put(0x064E, {});
    try arabic_group.cm.put(0x064E, {});
    
    // Test with various input sizes
    const test_sizes = [_]usize{ 1, 10, 50, 100, 500 };
    
    for (test_sizes) |size| {
        const test_input = try allocator.alloc(u32, size);
        defer allocator.free(test_input);
        
        // Fill with alternating Arabic letters and NSMs
        for (test_input, 0..) |*cp, i| {
            if (i % 2 == 0) {
                cp.* = 0x0628; // Arabic beh
            } else {
                cp.* = 0x064E; // Arabic fatha
            }
        }
        
        // Should complete quickly
        const start_time = std.time.nanoTimestamp();
        try nsm_validation.validateNSM(test_input, &groups, &arabic_group, allocator);
        const end_time = std.time.nanoTimestamp();
        
        // Should complete in reasonable time (less than 1ms for these sizes)
        const duration_ns = end_time - start_time;
        try testing.expect(duration_ns < 1_000_000); // 1ms
    }
}

test "NSM validation - edge cases" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    try groups.nsm_set.put(0x0300, {}); // Combining grave accent
    try latin_group.cm.put(0x0300, {});
    
    // Test NSM after control character
    const control_nsm = [_]u32{0x0001, 0x0300}; // Control char + NSM
    const result1 = nsm_validation.validateNSM(&control_nsm, &groups, &latin_group, allocator);
    try testing.expectError(nsm_validation.NSMValidationError.InvalidNSMBase, result1);
    
    // Test NSM after format character  
    const format_nsm = [_]u32{0x200E, 0x0300}; // LTR mark + NSM
    const result2 = nsm_validation.validateNSM(&format_nsm, &groups, &latin_group, allocator);
    try testing.expectError(nsm_validation.NSMValidationError.InvalidNSMBase, result2);
}

test "NSM validation - load from actual data" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Load actual script groups from data
    var groups = try static_data_loader.loadScriptGroups(allocator);
    defer groups.deinit();
    
    // Test with actual NSM data
    if (groups.nsm_set.count() > 0) {
        // Find a real NSM from the data
        var iter = groups.nsm_set.iterator();
        if (iter.next()) |entry| {
            const nsm = entry.key_ptr.*;
            
            // Create a simple sequence with a base character + NSM
            const sequence = [_]u32{0x0061, nsm}; // 'a' + real NSM
            
            // Determine appropriate script group
            const test_cps = [_]u32{0x0061}; // Just 'a' for script detection
            const script_group = try groups.determineScriptGroup(&test_cps, allocator);
            
            // Test NSM validation (might fail due to script mismatch, but shouldn't crash)
            const result = nsm_validation.validateNSM(&sequence, &groups, script_group, allocator);
            
            // We expect either success or a specific NSM error, not a crash
            if (result) |_| {
                // Success case
                try testing.expect(true);
            } else |err| {
                // Should be a known NSM validation error
                const is_nsm_error = switch (err) {
                    nsm_validation.NSMValidationError.ExcessiveNSM,
                    nsm_validation.NSMValidationError.DuplicateNSM,
                    nsm_validation.NSMValidationError.LeadingNSM,
                    nsm_validation.NSMValidationError.NSMAfterEmoji,
                    nsm_validation.NSMValidationError.NSMAfterFenced,
                    nsm_validation.NSMValidationError.InvalidNSMBase,
                    nsm_validation.NSMValidationError.NSMOrderError,
                    nsm_validation.NSMValidationError.DisallowedNSMScript => true,
                };
                try testing.expect(is_nsm_error);
            }
        }
    }
}