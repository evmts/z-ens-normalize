const std = @import("std");
const ens = @import("ens_normalize");
const combining_marks = ens.combining_marks;
const script_groups = ens.script_groups;
const static_data_loader = ens.static_data_loader;
const validator = ens.validator;
const tokenizer = ens.tokenizer;
const code_points = ens.code_points;

test "combining marks - basic detection" {
    const testing = std.testing;
    
    // Test basic combining marks
    try testing.expect(combining_marks.isCombiningMark(0x0301)); // Combining acute accent
    try testing.expect(combining_marks.isCombiningMark(0x0300)); // Combining grave accent
    try testing.expect(combining_marks.isCombiningMark(0x064E)); // Arabic fatha
    
    // Test non-combining marks
    try testing.expect(!combining_marks.isCombiningMark('a'));
    try testing.expect(!combining_marks.isCombiningMark('A'));
    try testing.expect(!combining_marks.isCombiningMark(0x0041)); // Latin A
}

test "combining marks - leading CM validation" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a mock script group for testing
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    // Add combining mark to allowed set
    try latin_group.cm.put(0x0301, {});
    
    // Test leading combining mark (should fail)
    const leading_cm = [_]u32{0x0301, 'a'};
    const result = combining_marks.validateCombiningMarks(&leading_cm, &latin_group, allocator);
    try testing.expectError(combining_marks.ValidationError.LeadingCombiningMark, result);
}

test "combining marks - disallowed CM for script group" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a mock script group that doesn't allow Arabic CMs
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    // Don't add Arabic CM to allowed set
    
    // Test Arabic CM with Latin group (should fail)
    const wrong_script_cm = [_]u32{'a', 0x064E}; // Latin + Arabic fatha
    const result = combining_marks.validateCombiningMarks(&wrong_script_cm, &latin_group, allocator);
    try testing.expectError(combining_marks.ValidationError.DisallowedCombiningMark, result);
}

test "combining marks - CM after emoji validation" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var emoji_group = script_groups.ScriptGroup.init(allocator, "Emoji", 0);
    defer emoji_group.deinit();
    
    // Add combining mark to allowed set
    try emoji_group.cm.put(0x0301, {});
    
    // Test emoji + combining mark (should fail)
    const emoji_cm = [_]u32{0x1F600, 0x0301}; // Grinning face + acute
    const result = combining_marks.validateCombiningMarks(&emoji_cm, &emoji_group, allocator);
    try testing.expectError(combining_marks.ValidationError.CombiningMarkAfterEmoji, result);
}

test "combining marks - valid sequences" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    // Add combining marks to allowed set
    try latin_group.cm.put(0x0301, {}); // Acute accent
    try latin_group.cm.put(0x0300, {}); // Grave accent
    
    // Test valid sequences (should pass)
    const valid_sequences = [_][]const u32{
        &[_]u32{'a', 0x0301},      // á
        &[_]u32{'e', 0x0300},      // è  
        &[_]u32{'a', 0x0301, 0x0300}, // Multiple CMs
    };
    
    for (valid_sequences) |seq| {
        try combining_marks.validateCombiningMarks(seq, &latin_group, allocator);
    }
}

test "combining marks - Arabic diacritic validation" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);
    defer arabic_group.deinit();
    
    // Add Arabic combining marks
    try arabic_group.cm.put(0x064E, {}); // Fatha
    try arabic_group.cm.put(0x064F, {}); // Damma
    try arabic_group.cm.put(0x0650, {}); // Kasra
    try arabic_group.cm.put(0x0651, {}); // Shadda
    
    // Test valid Arabic with diacritics
    const valid_arabic = [_]u32{0x0628, 0x064E}; // بَ (beh + fatha)
    try combining_marks.validateCombiningMarks(&valid_arabic, &arabic_group, allocator);
    
    // Test excessive diacritics (should fail)
    const excessive = [_]u32{0x0628, 0x064E, 0x064F, 0x0650, 0x0651}; // Too many marks
    const result = combining_marks.validateCombiningMarks(&excessive, &arabic_group, allocator);
    try testing.expectError(combining_marks.ValidationError.ExcessiveArabicDiacritics, result);
}

test "combining marks - integration with full validation" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test Latin with accents (should work)
    {
        // Note: Using NFC-composed characters for now since our tokenizer expects pre-composed
        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "café", &specs, false);
        defer tokenized.deinit();
        
        const result = validator.validateLabel(allocator, tokenized, &specs);
        if (result) |validated| {
            defer validated.deinit();
            // Should pass - Latin script with proper accents
            try testing.expect(true);
        } else |err| {
            // Make sure it's not a combining mark error
            try testing.expect(err != validator.ValidationError.LeadingCombiningMark);
            try testing.expect(err != validator.ValidationError.DisallowedCombiningMark);
        }
    }
}

test "combining marks - empty input validation" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    const empty_cps = [_]u32{};
    try combining_marks.validateCombiningMarks(&empty_cps, &latin_group, allocator);
    // Should pass - nothing to validate
}

test "combining marks - no combining marks in input" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    // Just base characters, no CMs
    const no_cms = [_]u32{'h', 'e', 'l', 'l', 'o'};
    try combining_marks.validateCombiningMarks(&no_cms, &latin_group, allocator);
    // Should pass - no CMs to validate
}

test "combining marks - script-specific rules" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test Devanagari rules
    {
        var devanagari_group = script_groups.ScriptGroup.init(allocator, "Devanagari", 0);
        defer devanagari_group.deinit();
        
        try devanagari_group.cm.put(0x093E, {}); // Aa matra
        
        // Valid: consonant + vowel sign
        const valid_devanagari = [_]u32{0x0915, 0x093E}; // का (ka + aa-matra)
        try combining_marks.validateCombiningMarks(&valid_devanagari, &devanagari_group, allocator);
        
        // Invalid: vowel sign without consonant
        const invalid_devanagari = [_]u32{0x093E}; // Just matra
        const result = combining_marks.validateCombiningMarks(&invalid_devanagari, &devanagari_group, allocator);
        try testing.expectError(combining_marks.ValidationError.LeadingCombiningMark, result);
    }
    
    // Test Thai rules
    {
        var thai_group = script_groups.ScriptGroup.init(allocator, "Thai", 0);
        defer thai_group.deinit();
        
        try thai_group.cm.put(0x0E31, {}); // Mai han-akat
        
        // Valid: consonant + vowel sign
        const valid_thai = [_]u32{0x0E01, 0x0E31}; // ก + ั
        try combining_marks.validateCombiningMarks(&valid_thai, &thai_group, allocator);
    }
}

test "combining marks - performance test" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    // Add common combining marks
    try latin_group.cm.put(0x0301, {});
    try latin_group.cm.put(0x0300, {});
    
    // Test with various input sizes
    const test_sizes = [_]usize{ 1, 5, 10, 50, 100 };
    
    for (test_sizes) |size| {
        const test_cps = try allocator.alloc(u32, size);
        defer allocator.free(test_cps);
        
        // Fill with alternating base chars and combining marks
        for (test_cps, 0..) |*cp, i| {
            if (i % 2 == 0) {
                cp.* = 'a' + @as(u32, @intCast(i % 26));
            } else {
                cp.* = 0x0301; // Acute accent
            }
        }
        
        // Should complete quickly
        const start_time = std.time.nanoTimestamp();
        try combining_marks.validateCombiningMarks(test_cps, &latin_group, allocator);
        const end_time = std.time.nanoTimestamp();
        
        // Should complete in reasonable time (less than 1ms for these sizes)
        const duration_ns = end_time - start_time;
        try testing.expect(duration_ns < 1_000_000); // 1ms
    }
}

test "combining marks - edge cases" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    try latin_group.cm.put(0x0300, {}); // Grave accent
    try latin_group.cm.put(0x0308, {}); // Diaeresis
    
    // Test multiple valid CMs on one base
    const multiple_cms = [_]u32{'a', 0x0300, 0x0308}; // à̈ (grave + diaeresis)
    try combining_marks.validateCombiningMarks(&multiple_cms, &latin_group, allocator);
    
    // Test CM after fenced character (should fail)
    const fenced_cm = [_]u32{'.', 0x0300}; // Period + grave accent
    const result = combining_marks.validateCombiningMarks(&fenced_cm, &latin_group, allocator);
    try testing.expectError(combining_marks.ValidationError.CombiningMarkAfterFenced, result);
}

test "combining marks - load from actual data" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Load actual script groups from data
    var groups = try static_data_loader.loadScriptGroups(allocator);
    defer groups.deinit();
    
    // Test with actual script group data
    const latin_cps = [_]u32{'a', 'b', 'c'};
    const latin_group = try groups.determineScriptGroup(&latin_cps, allocator);
    
    // Test combining mark validation with real data
    if (latin_group.cm.count() > 0) {
        // Find a combining mark allowed by Latin script
        var iter = latin_group.cm.iterator();
        if (iter.next()) |entry| {
            const cm = entry.key_ptr.*;
            const valid_sequence = [_]u32{'a', cm};
            try combining_marks.validateCombiningMarks(&valid_sequence, latin_group, allocator);
        }
    }
}