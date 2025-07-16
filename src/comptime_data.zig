const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;

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

// Comptime perfect hash for character mappings
pub const CharacterMappingEntry = struct {
    from: CodePoint,
    to: []const CodePoint,
};

// Generate a sorted array of character mappings at compile time
pub const character_mappings = blk: {
    @setEvalBranchQuota(100000);
    const count = spec_data.mapped.len;
    var entries: [count]CharacterMappingEntry = undefined;
    
    for (spec_data.mapped, 0..) |mapping, i| {
        entries[i] = .{
            .from = mapping[0],
            .to = mapping[1],
        };
    }
    
    // Sort by 'from' codepoint for binary search
    const Context = struct {
        fn lessThan(_: void, a: CharacterMappingEntry, b: CharacterMappingEntry) bool {
            return a.from < b.from;
        }
    };
    std.sort.insertion(CharacterMappingEntry, &entries, {}, Context.lessThan);
    
    break :blk entries;
};

// Binary search for character mapping
pub fn getMappedCodePoints(cp: CodePoint) ?[]const CodePoint {
    var left: usize = 0;
    var right: usize = character_mappings.len;
    
    while (left < right) {
        const mid = left + (right - left) / 2;
        if (character_mappings[mid].from == cp) {
            return character_mappings[mid].to;
        } else if (character_mappings[mid].from < cp) {
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    
    return null;
}

// Comptime set for ignored characters
pub const ignored_chars = blk: {
    @setEvalBranchQuota(10000);
    var set = std.StaticBitSet(0x110000).initEmpty();
    for (spec_data.ignored) |cp| {
        set.set(cp);
    }
    break :blk set;
};

pub fn isIgnored(cp: CodePoint) bool {
    if (cp >= 0x110000) return false;
    return ignored_chars.isSet(cp);
}

// Comptime set for fenced characters
pub const fenced_chars = blk: {
    @setEvalBranchQuota(10000);
    var set = std.StaticBitSet(0x110000).initEmpty();
    for (spec_data.fenced) |item| {
        set.set(item[0]);
    }
    break :blk set;
};

pub fn isFenced(cp: CodePoint) bool {
    if (cp >= 0x110000) return false;
    return fenced_chars.isSet(cp);
}

// Comptime set for valid characters (from all groups)
pub const valid_chars = blk: {
    @setEvalBranchQuota(10000000); // Need very high quota for all Unicode characters
    var set = std.StaticBitSet(0x110000).initEmpty();
    
    for (spec_data.groups) |group| {
        // Add primary characters
        for (group.primary) |cp| {
            set.set(cp);
        }
        
        // Add secondary characters if present
        if (group.secondary) |secondary| {
            for (secondary) |cp| {
                set.set(cp);
            }
        }
    }
    
    break :blk set;
};

pub fn isValid(cp: CodePoint) bool {
    if (cp >= 0x110000) return false;
    return valid_chars.isSet(cp);
}

// Comptime emoji data structure
pub const EmojiEntry = struct {
    sequence: []const CodePoint,
    no_fe0f: []const CodePoint,
};

pub const emoji_sequences = blk: {
    @setEvalBranchQuota(50000);
    const count = spec_data.emoji.len;
    var entries: [count]EmojiEntry = undefined;
    
    for (spec_data.emoji, 0..) |seq, i| {
        // Calculate no_fe0f version
        var no_fe0f_count: usize = 0;
        for (seq) |cp| {
            if (cp != 0xFE0F) no_fe0f_count += 1;
        }
        
        var no_fe0f: [no_fe0f_count]CodePoint = undefined;
        var j: usize = 0;
        for (seq) |cp| {
            if (cp != 0xFE0F) {
                no_fe0f[j] = cp;
                j += 1;
            }
        }
        
        entries[i] = .{
            .sequence = seq,
            .no_fe0f = &no_fe0f,
        };
    }
    
    break :blk entries;
};

// Comptime NFC decomposition data
pub const NFCDecompEntry = struct {
    cp: CodePoint,
    decomp: []const CodePoint,
};

pub const nfc_decompositions = blk: {
    @setEvalBranchQuota(50000);
    const count = nf_data.decomp.len;
    var entries: [count]NFCDecompEntry = undefined;
    
    for (nf_data.decomp, 0..) |entry, i| {
        entries[i] = .{
            .cp = entry[0],
            .decomp = entry[1],
        };
    }
    
    // Sort by codepoint for binary search
    const Context = struct {
        fn lessThan(_: void, a: NFCDecompEntry, b: NFCDecompEntry) bool {
            return a.cp < b.cp;
        }
    };
    std.sort.insertion(NFCDecompEntry, &entries, {}, Context.lessThan);
    
    break :blk entries;
};

pub fn getNFCDecomposition(cp: CodePoint) ?[]const CodePoint {
    var left: usize = 0;
    var right: usize = nfc_decompositions.len;
    
    while (left < right) {
        const mid = left + (right - left) / 2;
        if (nfc_decompositions[mid].cp == cp) {
            return nfc_decompositions[mid].decomp;
        } else if (nfc_decompositions[mid].cp < cp) {
            left = mid + 1;
        } else {
            right = mid;
        }
    }
    
    return null;
}

// Comptime NFC exclusions set
pub const nfc_exclusions = blk: {
    @setEvalBranchQuota(10000);
    var set = std.StaticBitSet(0x110000).initEmpty();
    for (nf_data.exclusions) |cp| {
        set.set(cp);
    }
    break :blk set;
};

pub fn isNFCExclusion(cp: CodePoint) bool {
    if (cp >= 0x110000) return false;
    return nfc_exclusions.isSet(cp);
}

// Comptime NFC check set
pub const nfc_check_set = blk: {
    @setEvalBranchQuota(10000);
    var set = std.StaticBitSet(0x110000).initEmpty();
    for (spec_data.nfc_check) |cp| {
        set.set(cp);
    }
    break :blk set;
};

pub fn needsNFCCheck(cp: CodePoint) bool {
    if (cp >= 0x110000) return false;
    return nfc_check_set.isSet(cp);
}

// Comptime NSM set
pub const nsm_set = blk: {
    @setEvalBranchQuota(10000);
    var set = std.StaticBitSet(0x110000).initEmpty();
    for (spec_data.nsm) |cp| {
        set.set(cp);
    }
    break :blk set;
};

pub fn isNSM(cp: CodePoint) bool {
    if (cp >= 0x110000) return false;
    return nsm_set.isSet(cp);
}

// Comptime combining marks set
pub const cm_set = blk: {
    @setEvalBranchQuota(10000);
    var set = std.StaticBitSet(0x110000).initEmpty();
    for (spec_data.cm) |cp| {
        set.set(cp);
    }
    break :blk set;
};

pub fn isCombiningMark(cp: CodePoint) bool {
    if (cp >= 0x110000) return false;
    return cm_set.isSet(cp);
}

// Comptime escape set
pub const escape_set = blk: {
    @setEvalBranchQuota(10000);
    var set = std.StaticBitSet(0x110000).initEmpty();
    for (spec_data.escape) |cp| {
        set.set(cp);
    }
    break :blk set;
};

pub fn needsEscape(cp: CodePoint) bool {
    if (cp >= 0x110000) return false;
    return escape_set.isSet(cp);
}

// Export spec data constants
pub const nsm_max = spec_data.nsm_max;
pub const spec_created = spec_data.created;
pub const spec_unicode = spec_data.unicode;
pub const spec_cldr = spec_data.cldr;

test "comptime character mappings" {
    const testing = std.testing;
    
    // Test that we can look up a mapping
    if (character_mappings.len > 0) {
        const first = character_mappings[0];
        const result = getMappedCodePoints(first.from);
        try testing.expect(result != null);
        try testing.expectEqualSlices(CodePoint, first.to, result.?);
    }
    
    // Test non-existent mapping
    const no_mapping = getMappedCodePoints(0xFFFFF);
    try testing.expect(no_mapping == null);
}

test "comptime sets" {
    const testing = std.testing;
    
    // Test ignored character
    if (spec_data.ignored.len > 0) {
        const first_ignored = spec_data.ignored[0];
        try testing.expect(isIgnored(first_ignored));
    }
    
    // Test non-ignored character
    try testing.expect(!isIgnored('A'));
    
    // Test fenced character
    if (spec_data.fenced.len > 0) {
        const first_fenced = spec_data.fenced[0][0];
        try testing.expect(isFenced(first_fenced));
    }
}