# Combining Mark Validation Per Group Implementation

## Overview

Combining marks (CM) are Unicode characters that modify the appearance of preceding base characters. Each script group has specific rules about which combining marks are allowed, and proper validation is crucial for preventing invalid Unicode sequences and visual spoofing attacks.

## The Problem

**Without proper CM validation:**
- Invalid Unicode sequences can be created (base character + wrong script's CM)
- Visual spoofing through unexpected mark combinations
- Inconsistent rendering across platforms
- Potential security issues with mark stacking

**Example Issues:**
- Latin "a" + Arabic combining mark = visually confusing
- Excessive combining marks creating unreadable text
- Emoji + combining marks (generally not allowed)

## Unicode Background

### Combining Mark Categories
```
Mark, Nonspacing (Mn): Doesn't take up space, positioned on base character
Mark, Spacing Combining (Mc): Takes up space, extends base character
Mark, Enclosing (Me): Surrounds or overlays base character
```

### Script-Specific Rules
```
Latin: Allows accents, diacritics (é, ñ, ü)
Arabic: Complex diacritic system (َ ِ ُ ً ٍ ٌ)
Devanagari: Vowel marks, tone marks
Thai: Vowel signs above/below consonants
```

## Current Data Structure

### From spec.zon - Script Groups with CM Data
```zig
// Example from loaded script groups
.{
    .name = "Latin",
    .primary = .{ 97, 98, 99 }, // a, b, c
    .secondary = .{ 192, 193 }, // À, Á  
    .cm = .{ 768, 769, 770 },   // Combining grave, acute, circumflex
}
```

### Current ScriptGroup Structure
```zig
pub const ScriptGroup = struct {
    name: []const u8,
    primary: std.AutoHashMap(CodePoint, void),
    secondary: std.AutoHashMap(CodePoint, void),
    combined: std.AutoHashMap(CodePoint, void),
    cm: std.AutoHashMap(CodePoint, void),        // ← This contains allowed CMs
    check_nsm: bool,
    index: usize,
    allocator: std.mem.Allocator,
};
```

## Reference Implementation Analysis

### JavaScript Reference (ens-normalize.js)
```javascript
// From ens-normalize.js validate.js
function check_group_rules(cps, group) {
    // Check combining marks are allowed for this group
    for (let cp of cps) {
        if (is_combining_mark(cp)) {
            if (!group_allows_cm(group, cp)) {
                throw new Error(`disallowed combining mark: ${cp} for group ${group.name}`);
            }
        }
    }
    
    // Check combining mark placement
    for (let i = 0; i < cps.length; i++) {
        let cp = cps[i];
        if (is_combining_mark(cp)) {
            if (i === 0) {
                throw new Error('leading combining mark');
            }
            let prev = cps[i-1];
            if (is_emoji(prev)) {
                throw new Error('combining mark after emoji');
            }
        }
    }
}
```

### Unicode TR29 Rules (Reference)
```
CM1: Combining marks must follow a base character
CM2: Multiple combining marks are ordered by combining class
CM3: Script-specific combining marks should match base script
CM4: Some contexts forbid combining marks (e.g., after emoji)
```

## Zig Implementation Plan

### 1. Enhanced Validation Functions

```zig
/// Validate combining marks for a specific script group
pub fn validateCombiningMarks(
    codepoints: []const CodePoint,
    script_group: *const script_groups.ScriptGroup,
    allocator: std.mem.Allocator
) ValidationError!void {
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
    // Rule CM4a: No combining marks after emoji
    if (isEmoji(base_cp)) {
        return ValidationError.CombiningMarkAfterEmoji;
    }
    
    // Rule CM4b: No combining marks after certain punctuation
    if (isFenced(base_cp)) {
        return ValidationError.CombiningMarkAfterFenced;
    }
    
    // Rule CM4c: Some combining marks have specific base requirements
    if (requiresSpecificBase(cm_cp) and !isValidBase(base_cp, cm_cp)) {
        return ValidationError.InvalidCombiningMarkBase;
    }
}

/// Script-specific combining mark rules
fn validateScriptSpecificCMRules(
    codepoints: []const CodePoint,
    script_group: *const script_groups.ScriptGroup
) ValidationError!void {
    if (std.mem.eql(u8, script_group.name, "Arabic")) {
        try validateArabicCMRules(codepoints);
    } else if (std.mem.eql(u8, script_group.name, "Devanagari")) {
        try validateDevanagaricCMRules(codepoints);
    } else if (std.mem.eql(u8, script_group.name, "Thai")) {
        try validateThaiCMRules(codepoints);
    }
    // Add more script-specific rules as needed
}

/// Arabic-specific combining mark validation
fn validateArabicCMRules(codepoints: []const CodePoint) ValidationError!void {
    // Arabic has complex diacritic rules
    var vowel_marks_count: usize = 0;
    var prev_was_consonant = false;
    
    for (codepoints) |cp| {
        if (isArabicVowelMark(cp)) {
            vowel_marks_count += 1;
            if (!prev_was_consonant) {
                return ValidationError.InvalidArabicDiacritic;
            }
            // Reset for next consonant
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
```

### 2. Enhanced Error Types

```zig
pub const ValidationError = error{
    // Existing errors...
    LeadingCombiningMark,
    CombiningMarkAfterEmoji,
    DisallowedCombiningMark,        // CM not allowed by script group
    CombiningMarkAfterFenced,       // CM after punctuation
    InvalidCombiningMarkBase,       // CM requires specific base type
    ExcessiveCombiningMarks,        // Too many CMs on one base
    InvalidArabicDiacritic,         // Arabic-specific CM rules
    ExcessiveArabicDiacritics,      // Too many Arabic vowel marks
    InvalidDevanagariMatras,        // Devanagari vowel sign rules
    InvalidThaiVowelSigns,          // Thai vowel placement rules
    CombiningMarkOrderError,        // Wrong canonical order
};
```

### 3. Unicode Property Detection

```zig
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
```

## Test Cases

### 1. Valid Cases (Should Pass)

```zig
test "cm validation - valid Latin with accents" {
    // "café" - Latin base + Latin combining marks
    const codepoints = [_]CodePoint{ 'c', 'a', 'f', 0x00E9 }; // é
    const latin_group = getLatinScriptGroup();
    try validateCombiningMarks(&codepoints, latin_group, allocator);
    // Should pass - proper Latin accents
}

test "cm validation - valid Arabic with diacritics" {
    // Arabic word with proper diacritics
    const codepoints = [_]CodePoint{ 0x0643, 0x064E, 0x062A, 0x064E, 0x0628 }; // كَتَب
    const arabic_group = getArabicScriptGroup();
    try validateCombiningMarks(&codepoints, arabic_group, allocator);
    // Should pass - proper Arabic diacritics
}

test "cm validation - valid Devanagari with matras" {
    // Devanagari with vowel signs
    const codepoints = [_]CodePoint{ 0x0915, 0x093E }; // का (ka + aa-matra)
    const devanagari_group = getDevanagariScriptGroup();
    try validateCombiningMarks(&codepoints, devanagari_group, allocator);
    // Should pass - proper Devanagari vowel sign
}
```

### 2. Invalid Cases (Should Fail)

```zig
test "cm validation - leading combining mark" {
    // Combining mark at start
    const codepoints = [_]CodePoint{ 0x0301, 'a' }; // ́a (acute accent + a)
    const latin_group = getLatinScriptGroup();
    const result = validateCombiningMarks(&codepoints, latin_group, allocator);
    try testing.expectError(ValidationError.LeadingCombiningMark, result);
}

test "cm validation - wrong script combining mark" {
    // Latin base + Arabic combining mark
    const codepoints = [_]CodePoint{ 'a', 0x064E }; // a + Arabic fatha
    const latin_group = getLatinScriptGroup();
    const result = validateCombiningMarks(&codepoints, latin_group, allocator);
    try testing.expectError(ValidationError.DisallowedCombiningMark, result);
}

test "cm validation - combining mark after emoji" {
    // Emoji + combining mark (not allowed)
    const codepoints = [_]CodePoint{ 0x1F600, 0x0301 }; // 😀 + acute accent
    const emoji_group = getEmojiScriptGroup();
    const result = validateCombiningMarks(&codepoints, emoji_group, allocator);
    try testing.expectError(ValidationError.CombiningMarkAfterEmoji, result);
}

test "cm validation - excessive Arabic diacritics" {
    // Too many Arabic vowel marks on one consonant
    const codepoints = [_]CodePoint{ 0x0643, 0x064E, 0x064F, 0x0650, 0x0651 }; // ك with 4 marks
    const arabic_group = getArabicScriptGroup();
    const result = validateCombiningMarks(&codepoints, arabic_group, allocator);
    try testing.expectError(ValidationError.ExcessiveArabicDiacritics, result);
}
```

### 3. Edge Cases

```zig
test "cm validation - empty input" {
    const codepoints = [_]CodePoint{};
    const latin_group = getLatinScriptGroup();
    try validateCombiningMarks(&codepoints, latin_group, allocator);
    // Should pass - nothing to validate
}

test "cm validation - no combining marks" {
    // Just base characters, no CMs
    const codepoints = [_]CodePoint{ 'h', 'e', 'l', 'l', 'o' };
    const latin_group = getLatinScriptGroup();
    try validateCombiningMarks(&codepoints, latin_group, allocator);
    // Should pass - no CMs to validate
}

test "cm validation - multiple valid CMs on one base" {
    // Base character with multiple allowed combining marks
    const codepoints = [_]CodePoint{ 'a', 0x0300, 0x0308 }; // à̈ (grave + diaeresis)
    const latin_group = getLatinScriptGroup();
    try validateCombiningMarks(&codepoints, latin_group, allocator);
    // Should pass if both CMs are allowed by Latin script
}
```

## Fuzz Testing Strategy

### 1. Property-Based Tests

```zig
test "cm fuzz - script consistency property" {
    // Property: All CMs in a label must be allowed by the detected script
    for (0..1000) |_| {
        const script = randomScript();
        const base_chars = randomBaseCharsFromScript(script, 5);
        const valid_cms = randomCMsFromScript(script, 3);
        
        var mixed_input = std.ArrayList(CodePoint).init(allocator);
        defer mixed_input.deinit();
        
        // Interleave base chars and valid CMs
        for (base_chars, 0..) |base, i| {
            try mixed_input.append(base);
            if (i < valid_cms.len) {
                try mixed_input.append(valid_cms[i]);
            }
        }
        
        // Should never fail for script-consistent CMs
        const script_group = getScriptGroup(script);
        try validateCombiningMarks(mixed_input.items, script_group, allocator);
    }
}

test "cm fuzz - no leading CM property" {
    // Property: Leading CM should always fail
    for (0..1000) |_| {
        const cm = randomCombiningMark();
        const base_chars = randomBaseChars(5);
        
        var input = std.ArrayList(CodePoint).init(allocator);
        defer input.deinit();
        
        try input.append(cm); // Leading CM
        try input.appendSlice(base_chars);
        
        // Should always fail with LeadingCombiningMark
        const script_group = randomScriptGroup();
        const result = validateCombiningMarks(input.items, script_group, allocator);
        try testing.expectError(ValidationError.LeadingCombiningMark, result);
    }
}

test "cm fuzz - emoji + CM always fails" {
    // Property: Emoji followed by CM should always fail
    for (0..1000) |_| {
        const emoji = randomEmoji();
        const cm = randomCombiningMark();
        
        const input = [_]CodePoint{ emoji, cm };
        
        const emoji_group = getEmojiScriptGroup();
        const result = validateCombiningMarks(&input, emoji_group, allocator);
        try testing.expectError(ValidationError.CombiningMarkAfterEmoji, result);
    }
}
```

### 2. Mutation Testing

```zig
test "cm fuzz - mutate valid to invalid" {
    // Take valid CM sequences and mutate them
    const valid_sequences = [_][]const CodePoint{
        &[_]CodePoint{ 'a', 0x0301 },      // á
        &[_]CodePoint{ 'e', 0x0300 },      // è
        &[_]CodePoint{ 'n', 0x0303 },      // ñ
    };
    
    for (valid_sequences) |seq| {
        // Mutation 1: Prepend CM
        var mutated1 = std.ArrayList(CodePoint).init(allocator);
        defer mutated1.deinit();
        try mutated1.append(0x0301); // Leading CM
        try mutated1.appendSlice(seq);
        
        const result1 = validateCombiningMarks(mutated1.items, getLatinScriptGroup(), allocator);
        try testing.expectError(ValidationError.LeadingCombiningMark, result1);
        
        // Mutation 2: Wrong script CM
        var mutated2 = std.ArrayList(CodePoint).init(allocator);
        defer mutated2.deinit();
        try mutated2.append(seq[0]); // Base char
        try mutated2.append(0x064E); // Arabic fatha instead of Latin accent
        
        const result2 = validateCombiningMarks(mutated2.items, getLatinScriptGroup(), allocator);
        try testing.expectError(ValidationError.DisallowedCombiningMark, result2);
    }
}
```

### 3. Stress Testing

```zig
test "cm fuzz - excessive combining marks" {
    // Test with many combining marks on one base
    const base = 'a';
    const cms = [_]CodePoint{ 0x0300, 0x0301, 0x0302, 0x0303, 0x0304, 0x0305 };
    
    for (1..cms.len + 1) |count| {
        var input = std.ArrayList(CodePoint).init(allocator);
        defer input.deinit();
        
        try input.append(base);
        try input.appendSlice(cms[0..count]);
        
        const latin_group = getLatinScriptGroup();
        const result = validateCombiningMarks(input.items, latin_group, allocator);
        
        if (count <= 3) {
            // Should pass for reasonable numbers
            try result;
        } else {
            // Should fail for excessive numbers
            try testing.expectError(ValidationError.ExcessiveCombiningMarks, result);
        }
    }
}
```

### 4. Cross-Script Confusion Tests

```zig
test "cm fuzz - cross script confusable CMs" {
    // Test CMs that look similar across scripts
    const confusable_pairs = [_][2]CodePoint{
        [_]CodePoint{ 0x0301, 0x0341 }, // Latin acute vs combining acute tone mark
        [_]CodePoint{ 0x0300, 0x0340 }, // Latin grave vs combining grave tone mark  
        [_]CodePoint{ 0x0308, 0x0344 }, // Latin diaeresis vs combining double inverted breve
    };
    
    for (confusable_pairs) |pair| {
        const base = 'a';
        
        // Test with Latin script group
        const latin_input = [_]CodePoint{ base, pair[0] };
        const latin_result = validateCombiningMarks(&latin_input, getLatinScriptGroup(), allocator);
        
        // Test with wrong CM from confusable pair
        const wrong_input = [_]CodePoint{ base, pair[1] };
        const wrong_result = validateCombiningMarks(&wrong_input, getLatinScriptGroup(), allocator);
        
        // One should pass, one should fail (depending on which is valid for Latin)
        if (latin_result) |_| {
            // If first passes, second should fail
            try testing.expectError(ValidationError.DisallowedCombiningMark, wrong_result);
        } else |_| {
            // If first fails, test the reverse
            // (This is complex - depends on actual CM assignments)
        }
    }
}
```

## Invariants to Maintain

### 1. Structural Invariants
- **No leading CMs**: First character must not be a combining mark
- **CM script consistency**: All CMs must be allowed by the detected script group
- **Context validity**: CMs must follow appropriate base characters
- **Canonical order**: Multiple CMs on same base should be in canonical order

### 2. Script-Specific Invariants
- **Arabic**: Vowel marks only after consonants, limited count per consonant
- **Devanagari**: Vowel signs (matras) only after consonants, specific placement rules
- **Thai**: Vowel signs above/below consonants, tone marks after vowels
- **Latin**: Accent marks on vowels primarily, some on consonants

### 3. Security Invariants
- **No visual spoofing**: Invalid CM combinations that create confusing display
- **No emoji corruption**: CMs after emoji always rejected
- **No excessive stacking**: Reasonable limits on CMs per base character
- **Cross-script prevention**: CMs from wrong script always rejected

### 4. Performance Invariants
- **Linear complexity**: O(n) validation time where n = input length
- **Bounded memory**: No unbounded allocations during validation
- **Deterministic**: Same input always produces same result
- **Fast common case**: ASCII-only text validated quickly

## Implementation Priority

1. **Core CM validation** - Basic rules (no leading, script consistency)
2. **Context validation** - Emoji, fenced character rules
3. **Script-specific rules** - Arabic, Devanagari, Thai special cases
4. **Canonical ordering** - Ensure CMs are in proper Unicode order
5. **Performance optimization** - Optimize for common cases
6. **Comprehensive testing** - All fuzz tests and edge cases

## Integration Points

### Validator Integration
```zig
// In main validator, after script group determination
const script_group = try groups.determineScriptGroup(unique_cps, allocator);

// Add CM validation step
try validateCombiningMarks(cps, script_group, allocator);
```

### Error Message Enhancement
```zig
// Provide detailed error context
pub const CMValidationError = struct {
    error_type: ValidationError,
    position: usize,           // Position of problematic CM
    combining_mark: CodePoint, // The problematic CM
    base_char: ?CodePoint,     // Base character (if applicable)
    script_group: []const u8,  // Expected script group
};
```

This comprehensive CM validation will significantly improve our Unicode handling and bring us much closer to full ENSIP-15 compliance.