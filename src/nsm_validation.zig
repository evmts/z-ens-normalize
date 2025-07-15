const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const script_groups = @import("script_groups.zig");

/// NSM validation errors
pub const NSMValidationError = error{
    ExcessiveNSM,           // More than 4 NSMs per base character
    DuplicateNSM,           // Same NSM appears consecutively
    LeadingNSM,             // NSM at start of sequence
    NSMAfterEmoji,          // NSM following emoji (not allowed)
    NSMAfterFenced,         // NSM following fenced character
    InvalidNSMBase,         // NSM following inappropriate base character
    NSMOrderError,          // NSMs not in canonical order
    DisallowedNSMScript,    // NSM from wrong script group
};

/// NSM sequence information for validation
pub const NSMSequence = struct {
    base_char: CodePoint,
    nsms: []const CodePoint,
    script_group: *const script_groups.ScriptGroup,
    
    pub fn validate(self: NSMSequence) NSMValidationError!void {
        // Check NSM count (ENSIP-15: max 4 NSMs per base character)
        if (self.nsms.len > 4) {
            return NSMValidationError.ExcessiveNSM;
        }
        
        // Check for duplicate NSMs in sequence
        for (self.nsms, 0..) |nsm1, i| {
            for (self.nsms[i+1..]) |nsm2| {
                if (nsm1 == nsm2) {
                    return NSMValidationError.DuplicateNSM;
                }
            }
        }
        
        // Check if all NSMs are allowed by this script group
        for (self.nsms) |nsm| {
            if (!self.script_group.cm.contains(nsm)) {
                return NSMValidationError.DisallowedNSMScript;
            }
        }
        
        // TODO: Check canonical ordering when we have full Unicode data
        // For now, we assume input is already in canonical order
    }
};

/// Comprehensive NSM validation for ENSIP-15 compliance
pub fn validateNSM(
    codepoints: []const CodePoint,
    groups: *const script_groups.ScriptGroups,
    script_group: *const script_groups.ScriptGroup,
    allocator: std.mem.Allocator,
) NSMValidationError!void {
    _ = allocator; // Reserved for future use (NFD normalization, etc.)
    if (codepoints.len == 0) return;
    
    // Check for leading NSM
    if (groups.isNSM(codepoints[0])) {
        return NSMValidationError.LeadingNSM;
    }
    
    var i: usize = 0;
    while (i < codepoints.len) {
        const cp = codepoints[i];
        
        if (!groups.isNSM(cp)) {
            // This is a base character, collect following NSMs
            const nsm_start = i + 1;
            var nsm_end = nsm_start;
            
            // Find all consecutive NSMs following this base character
            while (nsm_end < codepoints.len and groups.isNSM(codepoints[nsm_end])) {
                nsm_end += 1;
            }
            
            if (nsm_end > nsm_start) {
                // We have NSMs following this base character
                const nsms = codepoints[nsm_start..nsm_end];
                
                // Validate context - check if base character can accept NSMs
                try validateNSMContext(cp, nsms);
                
                // Create NSM sequence and validate
                const sequence = NSMSequence{
                    .base_char = cp,
                    .nsms = nsms,
                    .script_group = script_group,
                };
                try sequence.validate();
                
                // Apply script-specific validation
                try validateScriptSpecificNSMRules(cp, nsms, script_group);
                
                // Move past all NSMs
                i = nsm_end;
            } else {
                i += 1;
            }
        } else {
            // This should not happen if we handle base characters correctly
            i += 1;
        }
    }
}

/// Validate NSM context (what base characters can accept NSMs)
fn validateNSMContext(base_cp: CodePoint, nsms: []const CodePoint) NSMValidationError!void {
    _ = nsms; // For future context-specific validations
    
    // Rule: No NSMs after emoji
    if (isEmoji(base_cp)) {
        return NSMValidationError.NSMAfterEmoji;
    }
    
    // Rule: No NSMs after certain punctuation
    if (isFenced(base_cp)) {
        return NSMValidationError.NSMAfterFenced;
    }
    
    // Rule: No NSMs after certain symbols or control characters
    if (isInvalidNSMBase(base_cp)) {
        return NSMValidationError.InvalidNSMBase;
    }
}

/// Script-specific NSM validation rules
fn validateScriptSpecificNSMRules(
    base_cp: CodePoint,
    nsms: []const CodePoint,
    script_group: *const script_groups.ScriptGroup,
) NSMValidationError!void {
    if (std.mem.eql(u8, script_group.name, "Arabic")) {
        try validateArabicNSMRules(base_cp, nsms);
    } else if (std.mem.eql(u8, script_group.name, "Hebrew")) {
        try validateHebrewNSMRules(base_cp, nsms);
    } else if (std.mem.eql(u8, script_group.name, "Devanagari")) {
        try validateDevanagariNSMRules(base_cp, nsms);
    }
}

/// Arabic-specific NSM validation
fn validateArabicNSMRules(base_cp: CodePoint, nsms: []const CodePoint) NSMValidationError!void {
    // Arabic NSM rules:
    // 1. Diacritics should only appear on Arabic letters
    // 2. Maximum 3 diacritics per consonant (more restrictive than general 4)
    // 3. Certain combinations are invalid
    
    if (!isArabicLetter(base_cp)) {
        return NSMValidationError.InvalidNSMBase;
    }
    
    if (nsms.len > 3) {
        return NSMValidationError.ExcessiveNSM;
    }
    
    // Check for invalid combinations
    var has_vowel_mark = false;
    var has_shadda = false;
    
    for (nsms) |nsm| {
        if (isArabicVowelMark(nsm)) {
            if (has_vowel_mark) {
                // Multiple vowel marks on same consonant
                return NSMValidationError.DuplicateNSM;
            }
            has_vowel_mark = true;
        }
        
        if (nsm == 0x0651) { // Arabic Shadda
            if (has_shadda) {
                return NSMValidationError.DuplicateNSM;
            }
            has_shadda = true;
        }
    }
}

/// Hebrew-specific NSM validation
fn validateHebrewNSMRules(base_cp: CodePoint, nsms: []const CodePoint) NSMValidationError!void {
    // Hebrew NSM rules:
    // 1. Points should only appear on Hebrew letters
    // 2. Specific point combinations
    
    if (!isHebrewLetter(base_cp)) {
        return NSMValidationError.InvalidNSMBase;
    }
    
    // Hebrew allows fewer NSMs per character
    if (nsms.len > 2) {
        return NSMValidationError.ExcessiveNSM;
    }
}

/// Devanagari-specific NSM validation  
fn validateDevanagariNSMRules(base_cp: CodePoint, nsms: []const CodePoint) NSMValidationError!void {
    // Devanagari NSM rules:
    // 1. Vowel signs should only appear on consonants
    // 2. Specific ordering requirements
    
    if (!isDevanagariConsonant(base_cp)) {
        return NSMValidationError.InvalidNSMBase;
    }
    
    if (nsms.len > 2) {
        return NSMValidationError.ExcessiveNSM;
    }
}

/// Check if codepoint is an emoji
fn isEmoji(cp: CodePoint) bool {
    return (cp >= 0x1F600 and cp <= 0x1F64F) or  // Emoticons
           (cp >= 0x1F300 and cp <= 0x1F5FF) or  // Miscellaneous Symbols and Pictographs
           (cp >= 0x1F680 and cp <= 0x1F6FF) or  // Transport and Map Symbols
           (cp >= 0x2600 and cp <= 0x26FF);      // Miscellaneous Symbols
}

/// Check if codepoint is a fenced character
fn isFenced(cp: CodePoint) bool {
    return cp == 0x002E or  // Period
           cp == 0x002C or  // Comma
           cp == 0x003A or  // Colon
           cp == 0x003B or  // Semicolon
           cp == 0x0021 or  // Exclamation mark
           cp == 0x003F;    // Question mark
}

/// Check if codepoint is invalid as NSM base
fn isInvalidNSMBase(cp: CodePoint) bool {
    // Control characters, format characters, etc.
    return (cp >= 0x0000 and cp <= 0x001F) or  // C0 controls
           (cp >= 0x007F and cp <= 0x009F) or  // C1 controls
           (cp >= 0x2000 and cp <= 0x200F) or  // General punctuation (some)
           (cp >= 0xFFF0 and cp <= 0xFFFF);    // Specials
}

/// Arabic letter detection
fn isArabicLetter(cp: CodePoint) bool {
    return (cp >= 0x0621 and cp <= 0x063A) or  // Arabic letters
           (cp >= 0x0641 and cp <= 0x064A) or  // Arabic letters continued
           (cp >= 0x0671 and cp <= 0x06D3) or  // Arabic letters extended
           (cp >= 0x06FA and cp <= 0x06FF);    // Arabic letters supplement
}

/// Arabic vowel mark detection
fn isArabicVowelMark(cp: CodePoint) bool {
    return (cp >= 0x064B and cp <= 0x0650) or  // Fathatan, Dammatan, Kasratan, Fatha, Damma, Kasra
           cp == 0x0652;                        // Sukun
}

/// Hebrew letter detection
fn isHebrewLetter(cp: CodePoint) bool {
    return (cp >= 0x05D0 and cp <= 0x05EA) or  // Hebrew letters
           (cp >= 0x05F0 and cp <= 0x05F2);    // Hebrew ligatures
}

/// Devanagari consonant detection
fn isDevanagariConsonant(cp: CodePoint) bool {
    return (cp >= 0x0915 and cp <= 0x0939) or  // Consonants
           (cp >= 0x0958 and cp <= 0x095F);    // Additional consonants
}

/// Enhanced NSM detection with Unicode categories
pub fn isNSM(cp: CodePoint) bool {
    // Unicode General Category Mn (Mark, nonspacing)
    // This is a more comprehensive check than the basic one
    return (cp >= 0x0300 and cp <= 0x036F) or  // Combining Diacritical Marks
           (cp >= 0x0483 and cp <= 0x0489) or  // Cyrillic combining marks
           (cp >= 0x0591 and cp <= 0x05BD) or  // Hebrew points
           (cp >= 0x05BF and cp <= 0x05BF) or  // Hebrew point
           (cp >= 0x05C1 and cp <= 0x05C2) or  // Hebrew points
           (cp >= 0x05C4 and cp <= 0x05C5) or  // Hebrew points
           (cp >= 0x05C7 and cp <= 0x05C7) or  // Hebrew point
           (cp >= 0x0610 and cp <= 0x061A) or  // Arabic marks
           (cp >= 0x064B and cp <= 0x065F) or  // Arabic diacritics
           (cp >= 0x0670 and cp <= 0x0670) or  // Arabic letter superscript alef
           (cp >= 0x06D6 and cp <= 0x06DC) or  // Arabic small high marks
           (cp >= 0x06DF and cp <= 0x06E4) or  // Arabic small high marks
           (cp >= 0x06E7 and cp <= 0x06E8) or  // Arabic small high marks
           (cp >= 0x06EA and cp <= 0x06ED) or  // Arabic small high marks
           (cp >= 0x0711 and cp <= 0x0711) or  // Syriac letter superscript alaph
           (cp >= 0x0730 and cp <= 0x074A) or  // Syriac points
           (cp >= 0x07A6 and cp <= 0x07B0) or  // Thaana points
           (cp >= 0x07EB and cp <= 0x07F3) or  // NKo combining marks
           (cp >= 0x0816 and cp <= 0x0819) or  // Samaritan marks
           (cp >= 0x081B and cp <= 0x0823) or  // Samaritan marks
           (cp >= 0x0825 and cp <= 0x0827) or  // Samaritan marks
           (cp >= 0x0829 and cp <= 0x082D) or  // Samaritan marks
           (cp >= 0x0859 and cp <= 0x085B) or  // Mandaic marks
           (cp >= 0x08E3 and cp <= 0x0902) or  // Arabic/Devanagari marks
           (cp >= 0x093A and cp <= 0x093A) or  // Devanagari vowel sign oe
           (cp >= 0x093C and cp <= 0x093C) or  // Devanagari sign nukta
           (cp >= 0x0941 and cp <= 0x0948) or  // Devanagari vowel signs
           (cp >= 0x094D and cp <= 0x094D) or  // Devanagari sign virama
           (cp >= 0x0951 and cp <= 0x0957) or  // Devanagari stress signs
           (cp >= 0x0962 and cp <= 0x0963);    // Devanagari vowel signs
}

// Tests
const testing = std.testing;

test "NSM validation - basic count limits" {
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
    const valid_seq = [_]CodePoint{0x0628, 0x064E, 0x064F, 0x0650}; // بَُِ
    try validateNSM(&valid_seq, &groups, &arabic_group, allocator);
    
    // Test invalid sequence: base + 5 NSMs (exceeds limit)
    const invalid_seq = [_]CodePoint{0x0628, 0x064E, 0x064F, 0x0650, 0x0651, 0x0652};
    const result = validateNSM(&invalid_seq, &groups, &arabic_group, allocator);
    try testing.expectError(NSMValidationError.ExcessiveNSM, result);
}

test "NSM validation - duplicate detection" {
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
    const duplicate_seq = [_]CodePoint{0x0628, 0x064E, 0x064E}; // ب + fatha + fatha
    const result = validateNSM(&duplicate_seq, &groups, &arabic_group, allocator);
    try testing.expectError(NSMValidationError.DuplicateNSM, result);
}

test "NSM validation - leading NSM detection" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);
    defer arabic_group.deinit();
    
    try groups.nsm_set.put(0x064E, {});
    
    // Test leading NSM
    const leading_nsm = [_]CodePoint{0x064E, 0x0628}; // fatha + ب
    const result = validateNSM(&leading_nsm, &groups, &arabic_group, allocator);
    try testing.expectError(NSMValidationError.LeadingNSM, result);
}

test "NSM validation - emoji context" {
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
    const emoji_nsm = [_]CodePoint{0x1F600, 0x064E}; // 😀 + fatha
    const result = validateNSM(&emoji_nsm, &groups, &emoji_group, allocator);
    try testing.expectError(NSMValidationError.NSMAfterEmoji, result);
}

test "NSM detection - comprehensive Unicode ranges" {
    // Test various NSM ranges
    try testing.expect(isNSM(0x0300)); // Combining grave accent
    try testing.expect(isNSM(0x064E)); // Arabic fatha
    try testing.expect(isNSM(0x05B4)); // Hebrew point hiriq
    try testing.expect(isNSM(0x093C)); // Devanagari nukta
    try testing.expect(isNSM(0x0951)); // Devanagari stress sign udatta
    
    // Test non-NSMs
    try testing.expect(!isNSM('a'));
    try testing.expect(!isNSM(0x0628)); // Arabic letter beh
    try testing.expect(!isNSM(0x05D0)); // Hebrew letter alef
}

test "NSM validation - script-specific rules" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    defer groups.deinit();
    
    var arabic_group = script_groups.ScriptGroup.init(allocator, "Arabic", 0);
    defer arabic_group.deinit();
    
    try groups.nsm_set.put(0x064E, {});
    try groups.nsm_set.put(0x064F, {});
    try groups.nsm_set.put(0x0650, {});
    try groups.nsm_set.put(0x0651, {});
    
    try arabic_group.cm.put(0x064E, {});
    try arabic_group.cm.put(0x064F, {});
    try arabic_group.cm.put(0x0650, {});
    try arabic_group.cm.put(0x0651, {});
    
    // Test valid Arabic sequence
    const valid_arabic = [_]CodePoint{0x0628, 0x064E, 0x0651}; // بَّ (beh + fatha + shadda)
    try validateNSM(&valid_arabic, &groups, &arabic_group, allocator);
    
    // Test invalid: too many Arabic diacritics on one consonant
    const invalid_arabic = [_]CodePoint{0x0628, 0x064E, 0x064F, 0x0650, 0x0651}; // بَُِّ
    const result = validateNSM(&invalid_arabic, &groups, &arabic_group, allocator);
    try testing.expectError(NSMValidationError.ExcessiveNSM, result);
}