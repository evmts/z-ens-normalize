const std = @import("std");

/// Load spec data at compile time
const spec_zon = @embedFile("data/spec.zon");

/// Parsed spec data structure
pub const SpecData = struct {
    created: []const u8,
    unicode: []const u8,
    cldr: []const u8,
    emoji: []const []const u32,
    fenced: []const u32,
    ignored: []const u32,
    mapped: []const MappedChar,
    nfc_check: []const u32,
    nsm: []const u32,
    nsm_max: u32,
    cm: []const u32,
    wholes: []const Whole,
    groups: []const Group,
    
    pub const MappedChar = struct {
        cp: u32,
        mapped: []const u32,
    };
    
    pub const Whole = struct {
        valid: []const u32,
        confused: []const u32,
    };
    
    pub const Group = struct {
        name: []const u8,
        primary: []const u32,
        secondary: ?[]const u32 = null,
        cm: ?[]const u32 = null,
        restricted: ?bool = null,
    };
};

/// Parse spec at compile time
pub fn parseSpec() !SpecData {
    @setEvalBranchQuota(1_000_000);
    
    var diagnostics: std.zig.Ast.Diagnostics = .{};
    var ast = try std.zig.Ast.parse(std.heap.page_allocator, spec_zon, .zon, &diagnostics);
    defer ast.deinit(std.heap.page_allocator);
    
    if (diagnostics.errors.len > 0) {
        return error.ParseError;
    }
    
    // For now, return a placeholder
    // TODO: Implement actual ZON parsing
    return SpecData{
        .created = "",
        .unicode = "",
        .cldr = "",
        .emoji = &.{},
        .fenced = &.{},
        .ignored = &.{},
        .mapped = &.{},
        .nfc_check = &.{},
        .nsm = &.{},
        .nsm_max = 4,
        .cm = &.{},
        .wholes = &.{},
        .groups = &.{},
    };
}

/// Get spec data (parsed once at compile time)
pub const spec = parseSpec() catch @panic("Failed to parse spec.zon");

/// Script group enum for the most common scripts
pub const ScriptGroup = enum(u8) {
    Latin,
    Greek,
    Cyrillic,
    Hebrew,
    Arabic,
    Devanagari,
    Bengali,
    Gurmukhi,
    Gujarati,
    Tamil,
    Telugu,
    Kannada,
    Malayalam,
    Thai,
    Lao,
    Tibetan,
    Myanmar,
    Georgian,
    Hangul,
    Hiragana,
    Katakana,
    Han,
    Emoji,
    ASCII,
    Other,
    
    pub fn fromName(name: []const u8) ScriptGroup {
        inline for (@typeInfo(ScriptGroup).Enum.fields) |field| {
            if (std.mem.eql(u8, field.name, name)) {
                return @enumFromInt(field.value);
            }
        }
        return .Other;
    }
    
    pub fn toString(self: ScriptGroup) []const u8 {
        return @tagName(self);
    }
};