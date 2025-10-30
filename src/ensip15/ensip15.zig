//! ENSIP15 Normalization Methods
//!
//! This file contains the main normalization pipeline and validation logic
//! for ENS name normalization according to ENSIP15 specification.
//!
//! The normalization process:
//! 1. Split name by dots into labels
//! 2. For each label: tokenize → normalize → validate
//! 3. Join labels back with dots
//!
//! Note: This is a STUB implementation. All methods use @panic("TODO: implement")
//! and will be implemented in future tasks.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import types from other modules
const types = @import("types.zig");
const OutputToken = types.OutputToken;
const Group = types.Group;
const EmojiSequence = types.EmojiSequence;
const EmojiNode = types.EmojiNode;
const Whole = types.Whole;

const errors = @import("errors.zig");
const Error = errors.Error;

const RuneSet = @import("../util/runeset.zig").RuneSet;
const utils = @import("utils.zig");

// ============================================================
// Main ENSIP15 Structure
// ============================================================

/// Main ENSIP15 normalization context
/// Contains all data structures needed for ENS name normalization
pub const Ensip15 = struct {
    allocator: Allocator,

    // Placeholder fields - these would be populated by Task 11 (ensip15-init)
    // For now, we just define the structure with fields needed for validation

    // Normalization context
    nf: ?*const @import("../nf/nf.zig").NF = null,

    // Character sets
    should_escape: RuneSet = undefined,
    ignored: RuneSet = undefined,
    combining_marks: RuneSet = undefined,
    non_spacing_marks: RuneSet = undefined,
    max_non_spacing_marks: usize = 4, // Default max NSM count
    nfc_check: RuneSet = undefined,

    // Character mappings
    fenced: std.AutoHashMap(u21, []const u8) = undefined,
    mapped: std.AutoHashMap(u21, []const u21) = undefined,

    // Script groups
    groups: []Group = &[_]Group{},

    // Emoji sequences
    emojis: []EmojiSequence = &[_]EmojiSequence{},
    emoji_root: ?*EmojiNode = null,

    // Confusable detection
    possibly_valid: RuneSet = undefined,
    wholes: []Whole = &[_]Whole{},
    confusables: std.AutoHashMap(u21, Whole) = undefined,
    unique_non_confusables: RuneSet = undefined,

    // Common group references
    _ASCII: ?*const Group = null,
    _EMOJI: ?*const Group = null,
    _LATIN: ?*const Group = null,
    _GREEK: ?*const Group = null,

    /// Initialize ENSIP15 normalization context
    /// Note: Stubbed for Task 11
    pub fn init(allocator: Allocator) !Ensip15 {
        return Ensip15{
            .allocator = allocator,
        };
    }

    /// Cleanup resources
    pub fn deinit(self: *Ensip15) void {
        _ = self;
        // TODO: Free all allocated resources
    }

    // ============================================================
    // Public API - Normalization Methods
    // ============================================================

    /// Normalize a name according to ENSIP15 specification
    ///
    /// Takes an input name and returns its normalized form.
    /// The normalized form is suitable for on-chain storage and comparison.
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for result
    ///   - name: Input name as UTF-8 bytes
    ///
    /// Returns: Normalized name as UTF-8 bytes
    ///
    /// Errors: See Error enum for all possible validation failures
    ///
    /// Example:
    ///   const result = try ensip15.normalize(allocator, "Nick.ETH");
    ///   defer allocator.free(result);
    ///   // result should be "nick.eth"
    ///
    /// Note: Currently stubbed with @panic
    pub fn normalize(self: *const Ensip15, allocator: Allocator, name: []const u8) ![]u8 {
        _ = self;
        _ = allocator;
        _ = name;
        @panic("TODO: implement normalize()");
    }

    /// Beautify a name according to ENSIP15 specification
    ///
    /// Similar to normalize() but produces a more visually appealing result.
    /// Uses beautified emoji forms (preserves FE0F variation selectors).
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for result
    ///   - name: Input name as UTF-8 bytes
    ///
    /// Returns: Beautified name as UTF-8 bytes
    ///
    /// Errors: See Error enum for all possible validation failures
    ///
    /// Example:
    ///   const result = try ensip15.beautify(allocator, "nick.eth");
    ///   defer allocator.free(result);
    ///
    /// Note: Currently stubbed with @panic
    pub fn beautify(self: *const Ensip15, allocator: Allocator, name: []const u8) ![]u8 {
        _ = self;
        _ = allocator;
        _ = name;
        @panic("TODO: implement beautify()");
    }

    // ============================================================
    // Internal Transformation Pipeline
    // ============================================================

    /// Internal transformation pipeline
    ///
    /// Orchestrates the normalization pipeline:
    /// 1. Split name by dots into labels
    /// 2. For each label:
    ///    a. Convert to codepoints
    ///    b. Tokenize into Text/Emoji tokens
    ///    c. Apply normalization function to text tokens
    ///    d. Apply emoji function to emoji tokens
    ///    e. Run normalizer function (validation + flattening)
    ///    f. Replace label with normalized form
    /// 3. Join labels back with dots
    ///
    /// This method is used by:
    /// - normalize() - uses NFC + normalized emoji
    /// - beautify() - uses NFC + beautified emoji
    /// - normalizeFragment() - uses NFC/NFD + normalized emoji
    ///
    /// Note: Currently stubbed with @panic
    fn transform(
        self: *const Ensip15,
        allocator: Allocator,
        name: []const u8,
        // TODO: Add function pointers for normalization strategies
        // nf: *const fn([]const u21) []u21,
        // ef: *const fn(EmojiSequence) []const u21,
        // normalizer: *const fn([]const OutputToken) error![]const u8,
    ) ![]u8 {
        _ = self;
        _ = allocator;
        _ = name;
        @panic("TODO: implement transform()");
    }

    /// Tokenize codepoints into OutputToken stream
    ///
    /// Takes a slice of codepoints and produces a sequence of OutputTokens.
    /// Each token is either:
    /// - A text token (codepoints that are not emoji)
    /// - An emoji token (recognized emoji sequence)
    ///
    /// The function applies:
    /// - NFC normalization to text tokens (via nf parameter)
    /// - Emoji normalization to emoji tokens (via ef parameter)
    /// - Filtering of ignored codepoints
    /// - Mapping of mapped codepoints
    ///
    /// Parameters:
    ///   - allocator: Memory allocator for output
    ///   - cps: Input codepoints
    ///   - nf: Normalization function (NFC or NFD)
    ///   - ef: Emoji extraction function (normalized or beautified)
    ///
    /// Returns: Slice of OutputTokens
    ///
    /// Note: Currently stubbed with @panic
    fn outputTokenize(
        self: *const Ensip15,
        allocator: Allocator,
        cps: []const u21,
        // nf: *const fn([]const u21) []u21,
        // ef: *const fn(EmojiSequence) []const u21,
    ) ![]OutputToken {
        _ = self;
        _ = allocator;
        _ = cps;
        @panic("TODO: implement outputTokenize()");
    }

    // ============================================================
    // Validation Functions - Standalone
    // ============================================================

    /// Check that underscores only appear at start of label
    ///
    /// Rule: Underscores must match regex /^_*[^_]*$/
    /// This means: zero or more underscores, followed by zero or more non-underscores
    ///
    /// Valid examples:
    ///   - "_test"    (leading underscore)
    ///   - "__abc"    (multiple leading underscores)
    ///   - "hello"    (no underscores)
    ///   - "___"      (only underscores)
    ///
    /// Invalid examples:
    ///   - "ab_c"     (underscore in middle)
    ///   - "test_"    (trailing underscore)
    ///   - "_a_b"     (underscore after non-underscore)
    ///
    /// Algorithm:
    /// 1. Start with allowed = true
    /// 2. For each codepoint:
    ///    - If allowed and cp != underscore: allowed = false
    ///    - If not allowed and cp == underscore: ERROR
    fn checkLeadingUnderscore(cps: []const u21) !void {
        const UNDERSCORE: u21 = 0x5F;
        var allowed = true;
        for (cps) |cp| {
            if (allowed) {
                if (cp != UNDERSCORE) {
                    allowed = false;
                }
            } else {
                if (cp == UNDERSCORE) {
                    return Error.LeadingUnderscore;
                }
            }
        }
    }

    /// Check label extension format
    ///
    /// Rule: The 3rd and 4th characters (indices 2-3) cannot both be hyphens
    /// This prevents confusion with ACE prefix format (xn--).
    ///
    /// Valid examples:
    ///   - "ab-cd"    (single hyphen)
    ///   - "abc--d"   (hyphens not at positions 2-3)
    ///   - "-abc-"    (hyphens at other positions)
    ///   - "abc"      (no hyphens)
    ///
    /// Invalid examples:
    ///   - "xn--test" (positions 2-3 are both hyphens)
    ///   - "ab--cd"   (positions 2-3 are both hyphens)
    ///
    /// Algorithm:
    /// 1. If length < 4: valid (skip check)
    /// 2. If cps[2] == hyphen AND cps[3] == hyphen: ERROR
    fn checkLabelExtension(cps: []const u21) !void {
        const HYPHEN: u21 = 0x2D;
        if (cps.len >= 4 and cps[2] == HYPHEN and cps[3] == HYPHEN) {
            return Error.InvalidLabelExtension;
        }
    }

    // ============================================================
    // Validation Functions - Methods
    // ============================================================

    /// Check combining mark placement rules
    ///
    /// Combining marks cannot:
    /// 1. Appear at the start of a label
    /// 2. Appear immediately after an emoji
    ///
    /// This validation operates on the token stream (not raw codepoints)
    /// because we need to know which tokens are emoji.
    ///
    /// Algorithm:
    /// 1. For each token in tokens:
    ///    a. If token is text (not emoji):
    ///       - If first codepoint is combining mark:
    ///         - If token is first (i == 0): ERROR (CM at start)
    ///         - Else if previous token is emoji: ERROR (CM after emoji)
    fn checkCombiningMarks(self: *const Ensip15, tokens: []const OutputToken) !void {
        for (tokens, 0..) |token, i| {
            if (token.emoji == null and token.codepoints.len > 0) {
                const cp = token.codepoints[0];
                if (self.combining_marks.contains(cp)) {
                    if (i == 0) {
                        return Error.CMLeading;
                    } else if (tokens[i - 1].emoji != null) {
                        return Error.CMAfterEmoji;
                    }
                }
            }
        }
    }

    /// Check fenced character placement (ZWJ/ZWNJ)
    ///
    /// Fenced characters (Zero Width Joiner and Zero Width Non-Joiner)
    /// have special placement rules. They cannot:
    /// 1. Appear at the start of a label
    /// 2. Appear at the end of a label
    /// 3. Appear adjacent to each other
    ///
    /// The self.fenced map contains the fenced codepoints and their names.
    ///
    /// Algorithm:
    /// 1. If first codepoint is fenced: ERROR (fenced leading)
    /// 2. Track lastPos = -1 and lastName
    /// 3. For each codepoint (starting at index 1):
    ///    a. If codepoint is fenced:
    ///       - If lastPos == current index: ERROR (fenced adjacent)
    ///       - Update lastPos = current index + 1
    ///       - Update lastName
    /// 4. If lastPos == length: ERROR (fenced trailing)
    fn checkFenced(self: *const Ensip15, cps: []const u21) !void {
        if (cps.len == 0) return;

        // Check first character
        if (self.fenced.get(cps[0])) |_| {
            return Error.FencedLeading;
        }

        var last_pos: i32 = -1;
        for (cps[1..], 1..) |cp, i| {
            if (self.fenced.get(cp)) |_| {
                if (last_pos == @as(i32, @intCast(i))) {
                    return Error.FencedAdjacent;
                }
                last_pos = @intCast(i + 1);
            }
        }

        if (last_pos == @as(i32, @intCast(cps.len))) {
            return Error.FencedTrailing;
        }
    }

    /// Orchestrate all label validation checks
    ///
    /// This is the main validation function that coordinates all checks:
    /// 1. Check for empty label
    /// 2. Check underscore rules
    /// 3. Determine label type (ASCII, Emoji, or Script)
    /// 4. For ASCII: check label extension
    /// 5. For Emoji-only: return EMOJI group
    /// 6. For Script/Mixed: check combining marks, fenced chars, groups, confusables
    ///
    /// Returns: The Group this label belongs to (ASCII, EMOJI, or script group)
    ///
    /// Algorithm:
    /// 1. If cps is empty: ERROR (empty label)
    /// 2. Check leading underscore rule
    /// 3. Determine if hasEmoji (tokens > 1 or first token is emoji)
    /// 4. If no emoji and all ASCII:
    ///    a. Check label extension
    ///    b. Return ASCII group
    /// 5. Extract chars (non-emoji codepoints)
    /// 6. If has emoji and no chars: Return EMOJI group
    /// 7. Check combining marks on tokens
    /// 8. Check fenced characters on cps
    /// 9. Get unique chars
    /// 10. Determine script group from unique chars
    /// 11. Check group-specific rules
    /// 12. Check whole confusables
    /// 13. Return group
    fn checkValidLabel(
        self: *const Ensip15,
        allocator: Allocator,
        cps: []const u21,
        tokens: []const OutputToken,
    ) !?*const Group {
        if (cps.len == 0) return Error.EmptyLabel;

        try checkLeadingUnderscore(cps);

        const has_emoji = tokens.len > 1 or tokens[0].emoji != null;
        if (!has_emoji and utils.isAscii(cps)) {
            try checkLabelExtension(cps);
            return self._ASCII;
        }

        // Extract non-emoji chars
        var chars = std.ArrayList(u21).init(allocator);
        defer chars.deinit();

        for (tokens) |token| {
            if (token.emoji == null) {
                try chars.appendSlice(token.codepoints);
            }
        }

        if (has_emoji and chars.items.len == 0) {
            return self._EMOJI;
        }

        try self.checkCombiningMarks(tokens);
        try self.checkFenced(cps);

        const unique = try utils.uniqueRunes(allocator, chars.items);
        defer allocator.free(unique);

        const group = try self.determineGroup(unique, allocator);
        try self.checkGroup(group, chars.items, allocator);
        try self.checkWhole(group, unique, allocator);

        return group;
    }

    // ============================================================
    // Helper Methods (stubs for future implementation)
    // ============================================================

    /// Determine which script group a set of codepoints belongs to
    fn determineGroup(self: *const Ensip15, unique: []const u21, allocator: Allocator) !*const Group {
        // Clone groups array
        var gs = try allocator.alloc(*const Group, self.groups.len);
        defer allocator.free(gs);

        for (self.groups, 0..) |*g, i| {
            gs[i] = g;
        }

        var prev = gs.len;
        for (unique) |cp| {
            var next: usize = 0;
            for (0..prev) |i| {
                if (gs[i].contains(cp)) {
                    gs[next] = gs[i];
                    next += 1;
                }
            }

            if (next == 0) {
                return Error.DisallowedCharacter;
            }

            prev = next;
            if (prev == 1) break;
        }

        return gs[0];
    }

    /// Check group-specific validation rules
    fn checkGroup(self: *const Ensip15, group: *const Group, chars: []const u21, allocator: Allocator) !void {
        // Verify all chars in group
        for (chars) |cp| {
            if (!group.contains(cp)) {
                return Error.IllegalMixture;
            }
        }

        // Check NSM if not CM whitelisted
        if (!group.cm_whitelisted) {
            if (self.nf) |nf| {
                const decomposed = try nf.nfd(allocator, chars);
                defer allocator.free(decomposed);

                var i: usize = 1;
                while (i < decomposed.len) {
                    if (self.non_spacing_marks.contains(decomposed[i])) {
                        var j = i + 1;
                        while (j < decomposed.len) : (j += 1) {
                            const cp = decomposed[j];
                            if (!self.non_spacing_marks.contains(cp)) break;

                            // Check for duplicates
                            for (decomposed[i..j]) |prev_cp| {
                                if (prev_cp == cp) {
                                    return Error.NSMDuplicate;
                                }
                            }
                        }

                        const n = j - i;
                        if (n > self.max_non_spacing_marks) {
                            return Error.NSMExcessive;
                        }

                        i = j;
                    } else {
                        i += 1;
                    }
                }
            }
        }
    }

    /// Check for whole confusable sequences
    /// Note: Stubbed - confusable detection not yet implemented
    fn checkWhole(self: *const Ensip15, group: *const Group, unique: []const u21, allocator: Allocator) !void {
        _ = self;
        _ = group;
        _ = unique;
        _ = allocator;
        // TODO: Implement confusable detection
        // For now, stub - no confusable checking
    }

    /// Convert codepoint to safe display string
    /// Note: Stubbed for future implementation
    fn safeCodepoint(self: *const Ensip15, cp: u21) []const u8 {
        _ = self;
        _ = cp;
        @panic("TODO: implement safeCodepoint()");
    }

    /// Convert codepoints to safe display string
    /// Note: Stubbed for future implementation
    fn safeImplode(self: *const Ensip15, cps: []const u21) []const u8 {
        _ = self;
        _ = cps;
        @panic("TODO: implement safeImplode()");
    }
};

// ============================================================
// Utility Functions (imported from utils.zig)
// ============================================================
// The following utility functions are provided by utils module:
// - utils.split() - Split name by dots into labels
// - utils.join() - Join labels with dots
// - utils.flattenTokens() - Flatten tokens into codepoint slice
// - utils.isAscii() - Check if all codepoints are ASCII
// - utils.uniqueRunes() - Get unique codepoints preserving order

// ============================================================
// Tests
// ============================================================

test "Ensip15 init and deinit" {
    const allocator = std.testing.allocator;
    var ensip15 = try Ensip15.init(allocator);
    defer ensip15.deinit();
    // Just verify it compiles
}

test "checkLeadingUnderscore - valid cases" {
    // Valid: leading underscores only
    try Ensip15.checkLeadingUnderscore(&[_]u21{ 0x5F, 0x5F, 0x61 }); // "__a"
    try Ensip15.checkLeadingUnderscore(&[_]u21{ 0x61, 0x62 }); // "ab"
    try Ensip15.checkLeadingUnderscore(&[_]u21{0x5F}); // "_"
    try Ensip15.checkLeadingUnderscore(&[_]u21{}); // empty
}

test "checkLeadingUnderscore - invalid cases" {
    // Invalid: underscore after non-underscore
    const result = Ensip15.checkLeadingUnderscore(&[_]u21{ 0x61, 0x5F }); // "a_"
    try std.testing.expectError(Error.LeadingUnderscore, result);

    const result2 = Ensip15.checkLeadingUnderscore(&[_]u21{ 0x5F, 0x61, 0x5F }); // "_a_"
    try std.testing.expectError(Error.LeadingUnderscore, result2);
}

test "checkLabelExtension - valid cases" {
    // Valid: not xn-- pattern
    try Ensip15.checkLabelExtension(&[_]u21{ 0x61, 0x62, 0x63 }); // "abc"
    try Ensip15.checkLabelExtension(&[_]u21{ 0x61, 0x62, 0x2D, 0x63 }); // "ab-c"
    try Ensip15.checkLabelExtension(&[_]u21{ 0x61, 0x62 }); // "ab" (too short)
    try Ensip15.checkLabelExtension(&[_]u21{ 0x2D, 0x2D, 0x2D, 0x61 }); // "---a"
}

test "checkLabelExtension - invalid cases" {
    // Invalid: xn-- pattern
    const result = Ensip15.checkLabelExtension(&[_]u21{ 0x78, 0x6E, 0x2D, 0x2D }); // "xn--"
    try std.testing.expectError(Error.InvalidLabelExtension, result);

    const result2 = Ensip15.checkLabelExtension(&[_]u21{ 0x61, 0x62, 0x2D, 0x2D, 0x63 }); // "ab--c"
    try std.testing.expectError(Error.InvalidLabelExtension, result2);
}
