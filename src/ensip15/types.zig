//! ENSIP15 Type Definitions
//!
//! This file contains the core types used in ENSIP15 normalization.
//! These types represent tokens, groups, emoji sequences, and other structures
//! needed for the normalization pipeline.

const std = @import("std");

/// Represents a single token in the output stream
/// Can be either a text token (codepoints) or an emoji token
pub const OutputToken = struct {
    /// Unicode codepoints for this token (if text)
    codepoints: []const u21,

    /// Pointer to emoji sequence (if emoji, null otherwise)
    emoji: ?*const EmojiSequence,

    pub fn init(codepoints: []const u21) OutputToken {
        return .{
            .codepoints = codepoints,
            .emoji = null,
        };
    }

    pub fn initEmoji(emoji: *const EmojiSequence) OutputToken {
        return .{
            .codepoints = &.{},
            .emoji = emoji,
        };
    }
};

/// Represents an emoji sequence with normalized and beautified forms
pub const EmojiSequence = struct {
    /// Normalized form (with FE0F stripped)
    normalized: []const u21,

    /// Beautified form (with FE0F preserved where appropriate)
    beautified: []const u21,

    /// Human-readable name for this emoji
    name: []const u8,
};

/// Represents a script group (e.g., Latin, Greek, Han)
pub const Group = struct {
    /// Index in the groups array (-1 for special groups like ASCII, EMOJI)
    index: i32,

    /// Whether this group is restricted
    restricted: bool,

    /// Name of the group (e.g., "Latin", "Greek")
    name: []const u8,

    /// Whether combining marks are whitelisted for this group
    cm_whitelisted: bool,

    /// Primary codepoints for this group
    /// Note: This would be a RuneSet in full implementation
    primary: void,

    /// Secondary codepoints for this group
    /// Note: This would be a RuneSet in full implementation
    secondary: void,
};

/// Represents a whole confusable sequence
pub const Whole = struct {
    /// The confusable sequence
    sequence: []const u21,

    /// The group this belongs to
    group: *const Group,
};

/// Node in the emoji trie tree
pub const EmojiNode = struct {
    /// Children nodes mapped by codepoint
    /// Note: This would be a HashMap in full implementation
    children: void,

    /// The emoji sequence at this node (if this is a leaf)
    emoji: ?*const EmojiSequence,
};

/// RuneSet placeholder - will be implemented in Task 02
pub const RuneSet = struct {
    pub fn contains(self: *const RuneSet, cp: u21) bool {
        _ = self;
        _ = cp;
        @panic("TODO: implement RuneSet.contains");
    }
};

/// ENSIP15 normalizer instance (stub)
/// Will be fully implemented in later tasks
pub const Ensip15 = struct {
    should_escape: RuneSet,
    combining_marks: RuneSet,
};
