const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const script_groups = @import("script_groups.zig");

/// Combining mark validation errors
pub const ValidationError = error{
    LeadingCombiningMark,
    CombiningMarkAfterEmoji,
    DisallowedCombiningMark,
    CombiningMarkAfterFenced,
    InvalidCombiningMarkBase,
    ExcessiveCombiningMarks,
    InvalidArabicDiacritic,
    ExcessiveArabicDiacritics,
    InvalidDevanagariMatras,
    InvalidThaiVowelSigns,
    CombiningMarkOrderError,
};

/// Validate combining marks for a specific script group
pub fn validateCombiningMarks(
    codepoints: []const CodePoint,
    script_group: *const script_groups.ScriptGroup,
    allocator: std.mem.Allocator,
) ValidationError!void {
    _ = allocator; // For future use in complex validations
    
    for (codepoints, 0..) |cp, i| {
        if (isCombiningMark(cp)) {
            // Rule CM1: No leading combining marks
            if (i == 0) {
                return ValidationError.LeadingCombiningMark;
            }
            
            // Rule CM3: CM must be allowed by this script group
            if (!script_group.cm.contains(cp)) {
                return ValidationError.DisallowedCombiningMark;
            }
            
            // Rule CM4: Check preceding character context
            const prev_cp = codepoints[i - 1];
            try validateCombiningMarkContext(prev_cp, cp);
        }
    }
    
    // Additional script-specific validation
    try validateScriptSpecificCMRules(codepoints, script_group);
}

/// Validate combining mark context (what it can follow)
fn validateCombiningMarkContext(base_cp: CodePoint, cm_cp: CodePoint) ValidationError!void {
    _ = cm_cp; // For future context-specific validations
    
    // Rule CM4a: No combining marks after emoji
    if (isEmoji(base_cp)) {
        return ValidationError.CombiningMarkAfterEmoji;
    }
    
    // Rule CM4b: No combining marks after certain punctuation
    if (isFenced(base_cp)) {
        return ValidationError.CombiningMarkAfterFenced;
    }
}

/// Script-specific combining mark rules
fn validateScriptSpecificCMRules(
    codepoints: []const CodePoint,
    script_group: *const script_groups.ScriptGroup,
) ValidationError!void {
    if (std.mem.eql(u8, script_group.name, "Arabic")) {
        try validateArabicCMRules(codepoints);
    } else if (std.mem.eql(u8, script_group.name, "Devanagari")) {
        try validateDevanagaricCMRules(codepoints);
    } else if (std.mem.eql(u8, script_group.name, "Thai")) {
        try validateThaiCMRules(codepoints);
    }
}

/// Arabic-specific combining mark validation
fn validateArabicCMRules(codepoints: []const CodePoint) ValidationError!void {
    var vowel_marks_count: usize = 0;
    var prev_was_consonant = false;
    
    for (codepoints) |cp| {
        if (isArabicVowelMark(cp)) {
            vowel_marks_count += 1;
            if (!prev_was_consonant) {
                return ValidationError.InvalidArabicDiacritic;
            }
            prev_was_consonant = false;
        } else if (isArabicConsonant(cp)) {
            vowel_marks_count = 0;
            prev_was_consonant = true;
        }
        
        // Limit vowel marks per consonant
        if (vowel_marks_count > 3) {
            return ValidationError.ExcessiveArabicDiacritics;
        }
    }
}

/// Devanagari-specific combining mark validation
fn validateDevanagaricCMRules(codepoints: []const CodePoint) ValidationError!void {
    for (codepoints, 0..) |cp, i| {
        if (isDevanagariMatra(cp)) {
            if (i == 0) {
                return ValidationError.InvalidDevanagariMatras;
            }
            const prev_cp = codepoints[i - 1];
            if (!isDevanagariConsonant(prev_cp)) {
                return ValidationError.InvalidDevanagariMatras;
            }
        }
    }
}

/// Thai-specific combining mark validation
fn validateThaiCMRules(codepoints: []const CodePoint) ValidationError!void {
    for (codepoints, 0..) |cp, i| {
        if (isThaiVowelSign(cp)) {
            if (i == 0) {
                return ValidationError.InvalidThaiVowelSigns;
            }
            const prev_cp = codepoints[i - 1];
            if (!isThaiConsonant(prev_cp)) {
                return ValidationError.InvalidThaiVowelSigns;
            }
        }
    }
}

/// Check if codepoint is a combining mark
pub fn isCombiningMark(cp: CodePoint) bool {
    // Unicode categories Mn, Mc, Me
    return (cp >= 0x0300 and cp <= 0x036F) or  // Combining Diacritical Marks
           (cp >= 0x1AB0 and cp <= 0x1AFF) or  // Combining Diacritical Marks Extended
           (cp >= 0x1DC0 and cp <= 0x1DFF) or  // Combining Diacritical Marks Supplement
           (cp >= 0x20D0 and cp <= 0x20FF) or  // Combining Diacritical Marks for Symbols
           isScriptSpecificCM(cp);
}

/// Check for script-specific combining marks
fn isScriptSpecificCM(cp: CodePoint) bool {
    return isArabicCM(cp) or 
           isDevanagaricCM(cp) or 
           isThaiCM(cp) or
           isHebrewCM(cp);
}

fn isArabicCM(cp: CodePoint) bool {
    return (cp >= 0x064B and cp <= 0x065F) or  // Arabic diacritics
           (cp >= 0x0670 and cp <= 0x0671) or  // Arabic superscript alef
           (cp >= 0x06D6 and cp <= 0x06ED);    // Arabic small high marks
}

fn isDevanagaricCM(cp: CodePoint) bool {
    return (cp >= 0x093A and cp <= 0x094F) or  // Devanagari vowel signs
           (cp >= 0x0951 and cp <= 0x0957);    // Devanagari stress signs
}

fn isThaiCM(cp: CodePoint) bool {
    return (cp >= 0x0E31 and cp <= 0x0E3A) or  // Thai vowel signs and tone marks
           (cp >= 0x0E47 and cp <= 0x0E4E);    // Thai tone marks
}

fn isHebrewCM(cp: CodePoint) bool {
    return (cp >= 0x05B0 and cp <= 0x05BD) or  // Hebrew points
           (cp >= 0x05BF and cp <= 0x05C7);    // Hebrew points and marks
}

/// Check if codepoint is an emoji
fn isEmoji(cp: CodePoint) bool {
    return (cp >= 0x1F600 and cp <= 0x1F64F) or  // Emoticons
           (cp >= 0x1F300 and cp <= 0x1F5FF) or  // Miscellaneous Symbols and Pictographs
           (cp >= 0x1F680 and cp <= 0x1F6FF) or  // Transport and Map Symbols
           (cp >= 0x1F700 and cp <= 0x1F77F) or  // Alchemical Symbols
           (cp >= 0x1F780 and cp <= 0x1F7FF) or  // Geometric Shapes Extended
           (cp >= 0x1F800 and cp <= 0x1F8FF) or  // Supplemental Arrows-C
           (cp >= 0x2600 and cp <= 0x26FF) or    // Miscellaneous Symbols
           (cp >= 0x2700 and cp <= 0x27BF);      // Dingbats
}

/// Check if codepoint is a fenced character (punctuation that shouldn't have CMs)
fn isFenced(cp: CodePoint) bool {
    return cp == 0x002E or  // Period
           cp == 0x002C or  // Comma
           cp == 0x003A or  // Colon
           cp == 0x003B or  // Semicolon
           cp == 0x0021 or  // Exclamation mark
           cp == 0x003F;    // Question mark
}

/// Arabic vowel marks
fn isArabicVowelMark(cp: CodePoint) bool {
    return (cp >= 0x064B and cp <= 0x0650) or  // Fathatan, Dammatan, Kasratan, Fatha, Damma, Kasra
           cp == 0x0652 or                      // Sukun
           cp == 0x0640;                        // Tatweel
}

/// Arabic consonants (simplified check)
fn isArabicConsonant(cp: CodePoint) bool {
    return (cp >= 0x0621 and cp <= 0x063A) or  // Arabic letters
           (cp >= 0x0641 and cp <= 0x064A);    // Arabic letters continued
}

/// Devanagari vowel signs (matras)
fn isDevanagariMatra(cp: CodePoint) bool {
    return (cp >= 0x093E and cp <= 0x094F) and cp != 0x0940;  // Vowel signs except invalid ones
}

/// Devanagari consonants
fn isDevanagariConsonant(cp: CodePoint) bool {
    return (cp >= 0x0915 and cp <= 0x0939) or  // Consonants
           (cp >= 0x0958 and cp <= 0x095F);    // Additional consonants
}

/// Thai vowel signs
fn isThaiVowelSign(cp: CodePoint) bool {
    return (cp >= 0x0E31 and cp <= 0x0E3A) or  // Vowel signs above and below
           cp == 0x0E47 or cp == 0x0E48 or     // Tone marks
           cp == 0x0E49 or cp == 0x0E4A or
           cp == 0x0E4B or cp == 0x0E4C;
}

/// Thai consonants
fn isThaiConsonant(cp: CodePoint) bool {
    return (cp >= 0x0E01 and cp <= 0x0E2E);  // Thai consonants
}

// Tests
const testing = std.testing;

test "combining mark detection" {
    // Test basic combining marks
    try testing.expect(isCombiningMark(0x0301)); // Combining acute accent
    try testing.expect(isCombiningMark(0x0300)); // Combining grave accent
    try testing.expect(isCombiningMark(0x064E)); // Arabic fatha
    
    // Test non-combining marks
    try testing.expect(!isCombiningMark('a'));
    try testing.expect(!isCombiningMark('A'));
    try testing.expect(!isCombiningMark(0x0041)); // Latin A
}

test "emoji detection" {
    try testing.expect(isEmoji(0x1F600)); // Grinning face
    try testing.expect(isEmoji(0x1F680)); // Rocket
    try testing.expect(!isEmoji('a'));
    try testing.expect(!isEmoji(0x0301)); // Combining accent
}

test "fenced character detection" {
    try testing.expect(isFenced('.'));
    try testing.expect(isFenced(','));
    try testing.expect(isFenced(':'));
    try testing.expect(!isFenced('a'));
    try testing.expect(!isFenced(0x0301));
}

test "script-specific combining mark detection" {
    // Arabic
    try testing.expect(isArabicCM(0x064E)); // Fatha
    try testing.expect(isArabicVowelMark(0x064E));
    try testing.expect(isArabicConsonant(0x0628)); // Beh
    
    // Devanagari  
    try testing.expect(isDevanagaricCM(0x093E)); // Aa matra
    try testing.expect(isDevanagariMatra(0x093E));
    try testing.expect(isDevanagariConsonant(0x0915)); // Ka
    
    // Thai
    try testing.expect(isThaiCM(0x0E31)); // Mai han-akat
    try testing.expect(isThaiVowelSign(0x0E31));
    try testing.expect(isThaiConsonant(0x0E01)); // Ko kai
}

test "leading combining mark validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a mock script group for testing
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    // Add combining mark to allowed set
    try latin_group.cm.put(0x0301, {});
    
    // Test leading combining mark (should fail)
    const leading_cm = [_]CodePoint{0x0301, 'a'};
    const result = validateCombiningMarks(&leading_cm, &latin_group, allocator);
    try testing.expectError(ValidationError.LeadingCombiningMark, result);
}

test "disallowed combining mark validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a mock script group that doesn't allow Arabic CMs
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    // Don't add Arabic CM to allowed set
    
    // Test Arabic CM with Latin group (should fail)
    const wrong_script_cm = [_]CodePoint{'a', 0x064E}; // Latin + Arabic fatha
    const result = validateCombiningMarks(&wrong_script_cm, &latin_group, allocator);
    try testing.expectError(ValidationError.DisallowedCombiningMark, result);
}

test "combining mark after emoji validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var emoji_group = script_groups.ScriptGroup.init(allocator, "Emoji", 0);
    defer emoji_group.deinit();
    
    // Add combining mark to allowed set
    try emoji_group.cm.put(0x0301, {});
    
    // Test emoji + combining mark (should fail)
    const emoji_cm = [_]CodePoint{0x1F600, 0x0301}; // Grinning face + acute
    const result = validateCombiningMarks(&emoji_cm, &emoji_group, allocator);
    try testing.expectError(ValidationError.CombiningMarkAfterEmoji, result);
}

test "valid combining mark sequences" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var latin_group = script_groups.ScriptGroup.init(allocator, "Latin", 0);
    defer latin_group.deinit();
    
    // Add combining marks to allowed set
    try latin_group.cm.put(0x0301, {}); // Acute accent
    try latin_group.cm.put(0x0300, {}); // Grave accent
    
    // Test valid sequences (should pass)
    const valid_sequences = [_][]const CodePoint{
        &[_]CodePoint{'a', 0x0301},      // á
        &[_]CodePoint{'e', 0x0300},      // è  
        &[_]CodePoint{'a', 0x0301, 0x0300}, // Multiple CMs
    };
    
    for (valid_sequences) |seq| {
        try validateCombiningMarks(seq, &latin_group, allocator);
    }
}

test "arabic diacritic validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);
    defer arabic_group.deinit();
    
    // Add Arabic combining marks
    try arabic_group.cm.put(0x064E, {}); // Fatha
    try arabic_group.cm.put(0x064F, {}); // Damma
    
    // Test valid Arabic with diacritics
    const valid_arabic = [_]CodePoint{0x0628, 0x064E}; // بَ (beh + fatha)
    try validateCombiningMarks(&valid_arabic, &arabic_group, allocator);
    
    // Test excessive diacritics (should fail)
    const excessive = [_]CodePoint{0x0628, 0x064E, 0x064F, 0x0650, 0x0651}; // Too many marks
    const result = validateCombiningMarks(&excessive, &arabic_group, allocator);
    try testing.expectError(ValidationError.ExcessiveArabicDiacritics, result);
}