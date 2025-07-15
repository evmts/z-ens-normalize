const std = @import("std");

/// The raw spec data loaded at compile time
pub const spec_data = @import("data/spec.zon");

/// Generate script group enum from spec data
pub const ScriptGroup = blk: {
    const groups = spec_data.groups;
    var fields: [groups.len]std.builtin.Type.EnumField = undefined;
    
    for (groups, 0..) |group, i| {
        fields[i] = .{
            .name = group.name,
            .value = i,
        };
    }
    
    break :blk @Type(.{
        .Enum = .{
            .tag_type = u8,
            .fields = &fields,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
};

/// Get script group by name
pub fn getScriptGroupByName(name: []const u8) ?ScriptGroup {
    inline for (@typeInfo(ScriptGroup).Enum.fields) |field| {
        if (std.mem.eql(u8, field.name, name)) {
            return @enumFromInt(field.value);
        }
    }
    return null;
}

/// Get script group name
pub fn getScriptGroupName(group: ScriptGroup) []const u8 {
    return @tagName(group);
}

/// Get script group index
pub fn getScriptGroupIndex(group: ScriptGroup) usize {
    return @intFromEnum(group);
}

/// Get script group data by enum
pub fn getScriptGroupData(group: ScriptGroup) ScriptGroupData {
    const index = getScriptGroupIndex(group);
    return ScriptGroupData{
        .name = spec_data.groups[index].name,
        .primary = spec_data.groups[index].primary,
        .secondary = spec_data.groups[index].secondary orelse &.{},
        .cm = spec_data.groups[index].cm orelse &.{},
        .restricted = spec_data.groups[index].restricted orelse false,
    };
}

pub const ScriptGroupData = struct {
    name: []const u8,
    primary: []const u32,
    secondary: []const u32,
    cm: []const u32,
    restricted: bool,
};

/// All mapped characters from spec
pub const mapped_characters = spec_data.mapped;

/// All ignored characters from spec
pub const ignored_characters = spec_data.ignored;

/// All fenced characters from spec
pub const fenced_characters = spec_data.fenced;

/// All emoji sequences from spec
pub const emoji_sequences = spec_data.emoji;

/// NSM characters and max count
pub const nsm_characters = spec_data.nsm;
pub const nsm_max = spec_data.nsm_max;

/// NFC check data
pub const nfc_check = spec_data.nfc_check;

/// Whole script confusables
pub const whole_confusables = spec_data.wholes;

/// CM characters
pub const cm_characters = spec_data.cm;

test "script group enum generation" {
    const testing = std.testing;
    
    // Test that we can get groups by name
    const latin = getScriptGroupByName("Latin");
    try testing.expect(latin != null);
    try testing.expectEqualStrings("Latin", getScriptGroupName(latin.?));
    
    // Test that we can get group data
    const latin_data = getScriptGroupData(latin.?);
    try testing.expect(latin_data.primary.len > 0);
}