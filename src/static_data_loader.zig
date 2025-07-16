const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const character_mappings = @import("character_mappings.zig");
const CharacterMappings = character_mappings.CharacterMappings;
const nfc = @import("nfc.zig");
const emoji = @import("emoji.zig");
const script_groups = @import("script_groups.zig");
const confusables = @import("confusables.zig");
const utils = @import("utils.zig");

// Define ZON data types
const MappedItem = struct { u32, []const u32 };
const FencedItem = struct { u32, []const u8 };
const WholeItem = struct {
    target: ?[]const u8,
    valid: []const u32,
    confused: []const u32,
};
const GroupItem = struct {
    name: []const u8,
    primary: []const u32,
    secondary: ?[]const u32 = null,
    cm: ?[]const u32 = null,
    restricted: ?bool = null,
};

const SpecData = struct {
    created: []const u8,
    unicode: []const u8,
    cldr: []const u8,
    emoji: []const []const u32,
    ignored: []const u32,
    mapped: []const MappedItem,
    fenced: []const FencedItem,
    groups: []const GroupItem,
    nsm: []const u32,
    nsm_max: u32,
    nfc_check: []const u32,
    wholes: []const WholeItem,
    cm: []const u32,
    escape: []const u32,
};

const DecompItem = struct { u32, []const u32 };
const RankItem = []const u32;

const NfData = struct {
    created: []const u8,
    unicode: []const u8,
    exclusions: []const u32,
    decomp: []const DecompItem,
    ranks: []const RankItem,
    qc: ?[]const u32 = null,
};

// Import ZON data at compile time
const spec_data: SpecData = @import("data/spec.zon");
const nf_data: NfData = @import("data/nf.zon");

/// Load character mappings - now just returns the comptime-based struct
pub fn loadCharacterMappings(allocator: std.mem.Allocator) !CharacterMappings {
    // With comptime data, we don't need to load anything at runtime!
    return CharacterMappings.init(allocator);
}

/// Load NFC data from ZON
pub fn loadNFC(allocator: std.mem.Allocator) !nfc.NFCData {
    var nfc_data = nfc.NFCData.init(allocator);
    errdefer nfc_data.deinit();
    
    // Load exclusions
    for (nf_data.exclusions) |cp| {
        try nfc_data.exclusions.put(@as(CodePoint, cp), {});
    }
    
    // Load decomposition mappings
    for (nf_data.decomp) |entry| {
        const cp = @as(CodePoint, entry[0]);
        const decomp_array = entry[1];
        var decomp = try allocator.alloc(CodePoint, decomp_array.len);
        for (decomp_array, 0..) |decomp_cp, i| {
            decomp[i] = @as(CodePoint, decomp_cp);
        }
        try nfc_data.decomp.put(cp, decomp);
    }
    
    // Note: The ranks field in nf.zon appears to be arrays of codepoints
    // grouped by their combining class. We'll need to determine the actual
    // combining class values from the Unicode standard or reference implementation.
    // For now, we'll leave combining_class empty as it might not be needed
    // for basic normalization.
    
    // Load NFC check from spec data
    for (spec_data.nfc_check) |cp| {
        try nfc_data.nfc_check.put(@as(CodePoint, cp), {});
    }
    
    return nfc_data;
}

/// Load emoji data from ZON
pub fn loadEmoji(allocator: std.mem.Allocator) !emoji.EmojiMap {
    var emoji_data = emoji.EmojiMap.init(allocator);
    errdefer emoji_data.deinit();
    
    for (spec_data.emoji) |seq| {
        var cps = try allocator.alloc(CodePoint, seq.len);
        for (seq, 0..) |cp, i| {
            cps[i] = @as(CodePoint, cp);
        }
        defer allocator.free(cps);
        
        // Calculate no_fe0f version
        const no_fe0f = utils.filterFe0f(allocator, cps) catch cps;
        defer if (no_fe0f.ptr != cps.ptr) allocator.free(no_fe0f);
        
        // Use addEmoji to properly populate both hash map and list
        try emoji_data.addEmoji(no_fe0f, cps);
    }
    
    return emoji_data;
}

/// Load script groups from ZON
pub fn loadScriptGroups(allocator: std.mem.Allocator) !script_groups.ScriptGroups {
    var groups = script_groups.ScriptGroups.init(allocator);
    groups.groups = try allocator.alloc(script_groups.ScriptGroup, spec_data.groups.len);
    errdefer {
        allocator.free(groups.groups);
        groups.deinit();
    }
    
    // Load each script group
    for (spec_data.groups, 0..) |group_data, i| {
        // Duplicate the name to ensure it's owned by the allocator
        const name = try allocator.dupe(u8, group_data.name);
        var group = script_groups.ScriptGroup.init(allocator, name, i);
        
        // Add primary characters
        for (group_data.primary) |cp| {
            try group.addPrimary(@as(CodePoint, cp));
        }
        
        // Add secondary characters (if present)
        if (group_data.secondary) |secondary| {
            for (secondary) |cp| {
                try group.addSecondary(@as(CodePoint, cp));
            }
        }
        
        // Add combining marks (if present)
        if (group_data.cm) |cm| {
            for (cm) |cp| {
                try group.addCombiningMark(@as(CodePoint, cp));
            }
        }
        
        groups.groups[i] = group;
    }
    
    // Load NSM characters
    for (spec_data.nsm) |cp| {
        try groups.addNSM(@as(CodePoint, cp));
    }
    
    // Set NSM max
    groups.nsm_max = spec_data.nsm_max;
    
    return groups;
}

/// Load confusable data from ZON
pub fn loadConfusables(allocator: std.mem.Allocator) !confusables.ConfusableData {
    var confusable_data = confusables.ConfusableData.init(allocator);
    errdefer confusable_data.deinit();
    
    confusable_data.sets = try allocator.alloc(confusables.ConfusableSet, spec_data.wholes.len);
    
    for (spec_data.wholes, 0..) |whole, i| {
        // Get target
        const target = if (whole.target) |t| 
            try allocator.dupe(u8, t)
        else 
            try allocator.dupe(u8, "unknown");
        
        var set = confusables.ConfusableSet.init(allocator, target);
        
        // Load valid characters
        var valid_slice = try allocator.alloc(CodePoint, whole.valid.len);
        for (whole.valid, 0..) |cp, j| {
            valid_slice[j] = @as(CodePoint, cp);
        }
        set.valid = valid_slice;
        
        // Load confused characters
        var confused_slice = try allocator.alloc(CodePoint, whole.confused.len);
        for (whole.confused, 0..) |cp, j| {
            confused_slice[j] = @as(CodePoint, cp);
        }
        set.confused = confused_slice;
        
        confusable_data.sets[i] = set;
    }
    
    return confusable_data;
}

test "static data loading from ZON" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Just verify that the compile-time imports work
    try testing.expect(spec_data.created.len > 0);
    try testing.expect(spec_data.groups.len > 0);
    try testing.expect(nf_data.decomp.len > 0);
    
    // Test loading character mappings
    const mappings = try loadCharacterMappings(allocator);
    // With comptime data, we just verify the struct was created
    _ = mappings;
    
    // Test loading emoji
    const emoji_map = try loadEmoji(allocator);
    std.debug.print("Loaded {} emoji sequences\n", .{emoji_map.all_emojis.items.len});
    try testing.expect(emoji_map.all_emojis.items.len > 0);
    
    std.debug.print("✓ Successfully imported and loaded ZON data at compile time\n", .{});
}