const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;

pub const ProcessError = error{
    Confused,
    ConfusedGroups,
    CurrableError,
    DisallowedSequence,
    OutOfMemory,
    InvalidUtf8,
    InvalidCodePoint,
};

pub const ProcessErrorInfo = union(ProcessError) {
    Confused: struct {
        message: []const u8,
    },
    ConfusedGroups: struct {
        group1: []const u8,
        group2: []const u8,
    },
    CurrableError: struct {
        inner: CurrableError,
        index: usize,
        sequence: []const u8,
        maybe_suggest: ?[]const u8,
    },
    DisallowedSequence: DisallowedSequence,
    OutOfMemory: void,
    InvalidUtf8: void,
    InvalidCodePoint: void,
};

pub const CurrableError = enum {
    UnderscoreInMiddle,
    HyphenAtSecondAndThird,
    CmStart,
    CmAfterEmoji,
    FencedLeading,
    FencedTrailing,
    FencedConsecutive,
};

pub const DisallowedSequence = enum {
    Invalid,
    InvisibleCharacter,
    EmptyLabel,
    NsmTooMany,
    NsmRepeated,
};

pub const DisallowedSequenceInfo = union(DisallowedSequence) {
    Invalid: struct {
        message: []const u8,
    },
    InvisibleCharacter: struct {
        code_point: CodePoint,
    },
    EmptyLabel: void,
    NsmTooMany: void,
    NsmRepeated: void,
};

pub fn formatProcessError(
    allocator: std.mem.Allocator,
    error_info: ProcessErrorInfo,
) ![]u8 {
    switch (error_info) {
        .Confused => |info| {
            return try std.fmt.allocPrint(
                allocator,
                "contains visually confusing characters from multiple scripts: {s}",
                .{info.message},
            );
        },
        .ConfusedGroups => |info| {
            return try std.fmt.allocPrint(
                allocator,
                "contains visually confusing characters from {s} and {s} scripts",
                .{ info.group1, info.group2 },
            );
        },
        .CurrableError => |info| {
            var suggest_part: []const u8 = "";
            if (info.maybe_suggest) |suggest| {
                suggest_part = try std.fmt.allocPrint(
                    allocator,
                    " (suggestion: {s})",
                    .{suggest},
                );
            }
            return try std.fmt.allocPrint(
                allocator,
                "invalid character ('{s}') at position {d}: {s}{s}",
                .{ info.sequence, info.index, formatCurrableError(info.inner), suggest_part },
            );
        },
        .DisallowedSequence => |seq| {
            return try formatDisallowedSequence(allocator, seq);
        },
        .OutOfMemory => return try allocator.dupe(u8, "out of memory"),
        .InvalidUtf8 => return try allocator.dupe(u8, "invalid UTF-8"),
        .InvalidCodePoint => return try allocator.dupe(u8, "invalid code point"),
    }
}

fn formatCurrableError(err: CurrableError) []const u8 {
    return switch (err) {
        .UnderscoreInMiddle => "underscore in middle",
        .HyphenAtSecondAndThird => "hyphen at second and third position",
        .CmStart => "combining mark in disallowed position at the start of the label",
        .CmAfterEmoji => "combining mark in disallowed position after an emoji",
        .FencedLeading => "fenced character at the start of a label",
        .FencedTrailing => "fenced character at the end of a label",
        .FencedConsecutive => "consecutive sequence of fenced characters",
    };
}

fn formatDisallowedSequence(allocator: std.mem.Allocator, seq: DisallowedSequence) ![]u8 {
    return switch (seq) {
        .Invalid => try allocator.dupe(u8, "disallowed sequence"),
        .InvisibleCharacter => try allocator.dupe(u8, "invisible character"),
        .EmptyLabel => try allocator.dupe(u8, "empty label"),
        .NsmTooMany => try allocator.dupe(u8, "nsm too many"),
        .NsmRepeated => try allocator.dupe(u8, "nsm repeated"),
    };
}