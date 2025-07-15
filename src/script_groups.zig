const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const utils = @import("utils.zig");

/// Script group for validating character sets
pub const ScriptGroup = struct {
    /// Name of the script group (e.g., "Latin", "Greek", "Cyrillic")
    name: []const u8,
    /// Primary valid codepoints for this group
    primary: std.AutoHashMap(CodePoint, void),
    /// Secondary valid codepoints for this group
    secondary: std.AutoHashMap(CodePoint, void),
    /// Combined primary + secondary for quick lookup
    combined: std.AutoHashMap(CodePoint, void),
    /// Combining marks specific to this group (empty if none)
    cm: std.AutoHashMap(CodePoint, void),
    /// Whether to check NSM rules for this group
    check_nsm: bool,
    /// Index in the groups array (for error messages)
    index: usize,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8, index: usize) ScriptGroup {
        return ScriptGroup{
            .name = name,
            .primary = std.AutoHashMap(CodePoint, void).init(allocator),
            .secondary = std.AutoHashMap(CodePoint, void).init(allocator),
            .combined = std.AutoHashMap(CodePoint, void).init(allocator),
            .cm = std.AutoHashMap(CodePoint, void).init(allocator),
            .check_nsm = true, // Default to checking NSM
            .index = index,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ScriptGroup) void {
        self.primary.deinit();
        self.secondary.deinit();
        self.combined.deinit();
        self.cm.deinit();
        self.allocator.free(self.name);
    }
    
    /// Add a primary codepoint
    pub fn addPrimary(self: *ScriptGroup, cp: CodePoint) !void {
        try self.primary.put(cp, {});
        try self.combined.put(cp, {});
    }
    
    /// Add a secondary codepoint
    pub fn addSecondary(self: *ScriptGroup, cp: CodePoint) !void {
        try self.secondary.put(cp, {});
        try self.combined.put(cp, {});
    }
    
    /// Add a combining mark
    pub fn addCombiningMark(self: *ScriptGroup, cp: CodePoint) !void {
        try self.cm.put(cp, {});
    }
    
    /// Check if this group contains a codepoint (primary or secondary)
    pub fn containsCp(self: *const ScriptGroup, cp: CodePoint) bool {
        return self.combined.contains(cp);
    }
    
    /// Check if this group contains all codepoints
    pub fn containsAllCps(self: *const ScriptGroup, cps: []const CodePoint) bool {
        for (cps) |cp| {
            if (!self.containsCp(cp)) {
                return false;
            }
        }
        return true;
    }
    
    /// Check if a codepoint is in primary set
    pub fn isPrimary(self: *const ScriptGroup, cp: CodePoint) bool {
        return self.primary.contains(cp);
    }
    
    /// Check if a codepoint is in secondary set
    pub fn isSecondary(self: *const ScriptGroup, cp: CodePoint) bool {
        return self.secondary.contains(cp);
    }
};

/// Collection of all script groups
pub const ScriptGroups = struct {
    groups: []ScriptGroup,
    /// Set of all NSM (non-spacing marks) for validation
    nsm_set: std.AutoHashMap(CodePoint, void),
    /// Maximum consecutive NSM allowed
    nsm_max: u32,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ScriptGroups {
        return ScriptGroups{
            .groups = &[_]ScriptGroup{},
            .nsm_set = std.AutoHashMap(CodePoint, void).init(allocator),
            .nsm_max = 4, // Default from spec
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ScriptGroups) void {
        for (self.groups) |*group| {
            group.deinit();
        }
        self.allocator.free(self.groups);
        self.nsm_set.deinit();
    }
    
    /// Add NSM codepoint
    pub fn addNSM(self: *ScriptGroups, cp: CodePoint) !void {
        try self.nsm_set.put(cp, {});
    }
    
    /// Check if a codepoint is NSM
    pub fn isNSM(self: *const ScriptGroups, cp: CodePoint) bool {
        return self.nsm_set.contains(cp);
    }
    
    /// Find which groups contain a codepoint
    pub fn findGroupsContaining(self: *const ScriptGroups, cp: CodePoint, allocator: std.mem.Allocator) ![]const *const ScriptGroup {
        var matching = std.ArrayList(*const ScriptGroup).init(allocator);
        errdefer matching.deinit();
        
        for (self.groups) |*group| {
            if (group.containsCp(cp)) {
                try matching.append(group);
            }
        }
        
        return matching.toOwnedSlice();
    }
    
    /// Determine the script group for a set of unique codepoints
    pub fn determineScriptGroup(self: *const ScriptGroups, unique_cps: []const CodePoint, allocator: std.mem.Allocator) !*const ScriptGroup {
        if (unique_cps.len == 0) {
            return error.EmptyInput;
        }
        
        // Start with all groups
        var remaining = try allocator.alloc(*const ScriptGroup, self.groups.len);
        defer allocator.free(remaining);
        
        for (self.groups, 0..) |*group, i| {
            remaining[i] = group;
        }
        var remaining_count = self.groups.len;
        
        // Filter by each codepoint
        for (unique_cps) |cp| {
            var new_count: usize = 0;
            
            // Keep only groups that contain this codepoint
            for (remaining[0..remaining_count]) |group| {
                if (group.containsCp(cp)) {
                    remaining[new_count] = group;
                    new_count += 1;
                }
            }
            
            if (new_count == 0) {
                // No group contains this codepoint
                return error.DisallowedCharacter;
            }
            
            remaining_count = new_count;
        }
        
        // Return the first remaining group (highest priority)
        return remaining[0];
    }
};

/// Result of script group determination
pub const ScriptGroupResult = struct {
    group: *const ScriptGroup,
    mixed_scripts: bool,
};

/// Find conflicting groups when script mixing is detected
pub fn findConflictingGroups(
    groups: *const ScriptGroups,
    unique_cps: []const CodePoint,
    allocator: std.mem.Allocator
) !struct { first_group: *const ScriptGroup, conflicting_cp: CodePoint, conflicting_groups: []const *const ScriptGroup } {
    if (unique_cps.len == 0) {
        return error.EmptyInput;
    }
    
    // Find groups for first codepoint
    const remaining = try groups.findGroupsContaining(unique_cps[0], allocator);
    defer allocator.free(remaining);
    
    if (remaining.len == 0) {
        return error.DisallowedCharacter;
    }
    
    // Check each subsequent codepoint
    for (unique_cps[1..]) |cp| {
        const cp_groups = try groups.findGroupsContaining(cp, allocator);
        defer allocator.free(cp_groups);
        
        // Check if any remaining groups contain this cp
        var found = false;
        for (remaining) |group| {
            for (cp_groups) |cp_group| {
                if (group == cp_group) {
                    found = true;
                    break;
                }
            }
            if (found) break;
        }
        
        if (!found) {
            // This cp causes the conflict
            return .{
                .first_group = remaining[0],
                .conflicting_cp = cp,
                .conflicting_groups = cp_groups,
            };
        }
    }
    
    return error.NoConflict;
}

test "script group basic operations" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const name = try allocator.dupe(u8, "Latin");
    var group = ScriptGroup.init(allocator, name, 0);
    defer group.deinit();
    
    // Add some codepoints
    try group.addPrimary('A');
    try group.addPrimary('B');
    try group.addSecondary('1');
    try group.addSecondary('2');
    
    // Test contains
    try testing.expect(group.containsCp('A'));
    try testing.expect(group.containsCp('1'));
    try testing.expect(!group.containsCp('X'));
    
    // Test primary/secondary
    try testing.expect(group.isPrimary('A'));
    try testing.expect(!group.isPrimary('1'));
    try testing.expect(group.isSecondary('1'));
    try testing.expect(!group.isSecondary('A'));
}

test "script group determination" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = ScriptGroups.init(allocator);
    defer groups.deinit();
    
    // Create more realistic test groups with some overlap
    var test_groups = try allocator.alloc(ScriptGroup, 3);
    
    const latin_name = try allocator.dupe(u8, "Latin");
    test_groups[0] = ScriptGroup.init(allocator, latin_name, 0);
    try test_groups[0].addPrimary('A');
    try test_groups[0].addPrimary('B');
    try test_groups[0].addPrimary('C');
    try test_groups[0].addSecondary('0'); // Numbers are secondary in many scripts
    try test_groups[0].addSecondary('1');
    
    const greek_name = try allocator.dupe(u8, "Greek");
    test_groups[1] = ScriptGroup.init(allocator, greek_name, 1);
    try test_groups[1].addPrimary(0x03B1); // α
    try test_groups[1].addPrimary(0x03B2); // β
    try test_groups[1].addSecondary('0'); // Numbers are secondary in many scripts
    try test_groups[1].addSecondary('1');
    
    const common_name = try allocator.dupe(u8, "Common");
    test_groups[2] = ScriptGroup.init(allocator, common_name, 2);
    try test_groups[2].addPrimary('-');
    try test_groups[2].addPrimary('_');
    
    groups.groups = test_groups;
    
    // Test single script
    const latin_cps = [_]CodePoint{'A', 'B', 'C'};
    const latin_group = try groups.determineScriptGroup(&latin_cps, allocator);
    try testing.expectEqualStrings("Latin", latin_group.name);
    
    // Test Greek
    const greek_cps = [_]CodePoint{0x03B1, 0x03B2};
    const greek_group = try groups.determineScriptGroup(&greek_cps, allocator);
    try testing.expectEqualStrings("Greek", greek_group.name);
    
    // Test with common characters (numbers)
    const latin_with_numbers = [_]CodePoint{'A', '1'};
    const latin_num_group = try groups.determineScriptGroup(&latin_with_numbers, allocator);
    try testing.expectEqualStrings("Latin", latin_num_group.name);
    
    // Test mixed scripts (should error because no single group contains both)
    const mixed_cps = [_]CodePoint{'A', 0x03B1}; // Latin A + Greek α
    const result = groups.determineScriptGroup(&mixed_cps, allocator);
    try testing.expectError(error.DisallowedCharacter, result);
}