const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;

/// A set of confusable characters
pub const ConfusableSet = struct {
    target: []const u8,  // Target string (like "32" for the digit 2)
    valid: []const CodePoint,  // Valid characters for this confusable set
    confused: []const CodePoint,  // Characters that look like the valid ones
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, target: []const u8) ConfusableSet {
        return ConfusableSet{
            .target = target,
            .valid = &.{},
            .confused = &.{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ConfusableSet) void {
        self.allocator.free(self.target);
        self.allocator.free(self.valid);
        self.allocator.free(self.confused);
    }
    
    /// Check if this set contains the given codepoint (in valid or confused)
    pub fn contains(self: *const ConfusableSet, cp: CodePoint) bool {
        return self.containsValid(cp) or self.containsConfused(cp);
    }
    
    /// Check if this set contains the codepoint in the valid set
    pub fn containsValid(self: *const ConfusableSet, cp: CodePoint) bool {
        return std.mem.indexOfScalar(CodePoint, self.valid, cp) != null;
    }
    
    /// Check if this set contains the codepoint in the confused set
    pub fn containsConfused(self: *const ConfusableSet, cp: CodePoint) bool {
        return std.mem.indexOfScalar(CodePoint, self.confused, cp) != null;
    }
};

/// Collection of all confusable sets
pub const ConfusableData = struct {
    sets: []ConfusableSet,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ConfusableData {
        return ConfusableData{
            .sets = &.{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ConfusableData) void {
        for (self.sets) |*set| {
            set.deinit();
        }
        self.allocator.free(self.sets);
    }
    
    /// Find all confusable sets that contain any of the given codepoints
    pub fn findSetsContaining(self: *const ConfusableData, codepoints: []const CodePoint, allocator: std.mem.Allocator) ![]const *const ConfusableSet {
        var matching = std.ArrayList(*const ConfusableSet).init(allocator);
        errdefer matching.deinit();
        
        for (self.sets, 0..) |*set, i| {
            for (codepoints) |cp| {
                if (set.contains(cp)) {
                    _ = i; // Suppress unused variable warning
                    try matching.append(set);
                    break; // Found one, no need to check more codepoints for this set
                }
            }
        }
        
        return matching.toOwnedSlice();
    }
    
    /// Check if codepoints form a whole-script confusable (security violation)
    pub fn checkWholeScriptConfusables(self: *const ConfusableData, codepoints: []const CodePoint, allocator: std.mem.Allocator) !bool {
        if (codepoints.len == 0) return false; // Empty input is safe
        
        // Find all sets that contain any of our codepoints
        const matching_sets = try self.findSetsContaining(codepoints, allocator);
        defer allocator.free(matching_sets);
        
        
        if (matching_sets.len <= 1) {
            return false; // No confusables or all from same set - safe
        }
        
        // Check for dangerous mixing between different confusable sets
        // Key insight: mixing valid characters from different sets is OK
        // Only mixing when at least one confused character is present is dangerous
        
        var has_confused = false;
        for (codepoints) |cp| {
            for (matching_sets) |set| {
                if (set.containsConfused(cp)) {
                    has_confused = true;
                    break;
                }
            }
            if (has_confused) break;
        }
        
        // If there are no confused characters, it's safe even with multiple sets
        if (!has_confused) {
            return false;
        }
        
        // Now check if we're mixing characters from different sets
        // when at least one confused character is present
        for (matching_sets, 0..) |set1, i| {
            for (matching_sets[i+1..]) |set2| {
                // Check if we have characters from both sets
                var has_from_set1 = false;
                var has_from_set2 = false;
                
                for (codepoints) |cp| {
                    if (set1.contains(cp)) has_from_set1 = true;
                    if (set2.contains(cp)) has_from_set2 = true;
                    
                    // Early exit if we found both
                    if (has_from_set1 and has_from_set2) {
                        return true; // DANGEROUS: mixing confusable sets with confused characters
                    }
                }
            }
        }
        
        return false; // Safe
    }
    
    /// Get diagnostic information about confusable usage
    pub fn analyzeConfusables(self: *const ConfusableData, codepoints: []const CodePoint, allocator: std.mem.Allocator) !ConfusableAnalysis {
        var analysis = ConfusableAnalysis.init(allocator);
        errdefer analysis.deinit();
        
        const matching_sets = try self.findSetsContaining(codepoints, allocator);
        defer allocator.free(matching_sets);
        
        analysis.sets_involved = try allocator.dupe(*const ConfusableSet, matching_sets);
        analysis.is_confusable = matching_sets.len > 1;
        
        // Count characters by type
        for (codepoints) |cp| {
            var found_in_set = false;
            for (matching_sets) |set| {
                if (set.containsValid(cp)) {
                    analysis.valid_count += 1;
                    found_in_set = true;
                    break;
                } else if (set.containsConfused(cp)) {
                    analysis.confused_count += 1;
                    found_in_set = true;
                    break;
                }
            }
            if (!found_in_set) {
                analysis.non_confusable_count += 1;
            }
        }
        
        return analysis;
    }
};

/// Analysis result for confusable detection
pub const ConfusableAnalysis = struct {
    sets_involved: []const *const ConfusableSet,
    is_confusable: bool,
    valid_count: usize,
    confused_count: usize,
    non_confusable_count: usize,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ConfusableAnalysis {
        return ConfusableAnalysis{
            .sets_involved = &.{},
            .is_confusable = false,
            .valid_count = 0,
            .confused_count = 0,
            .non_confusable_count = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ConfusableAnalysis) void {
        self.allocator.free(self.sets_involved);
    }
};

test "confusable set basic operations" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var set = ConfusableSet.init(allocator, try allocator.dupe(u8, "test"));
    defer set.deinit();
    
    // Add some test data
    var valid_data = try allocator.alloc(CodePoint, 2);
    valid_data[0] = 'a';
    valid_data[1] = 'b';
    set.valid = valid_data;
    
    var confused_data = try allocator.alloc(CodePoint, 2);
    confused_data[0] = 0x0430; // Cyrillic 'а'
    confused_data[1] = 0x0431; // Cyrillic 'б'
    set.confused = confused_data;
    
    // Test containment
    try testing.expect(set.contains('a'));
    try testing.expect(set.contains(0x0430));
    try testing.expect(!set.contains('z'));
    
    try testing.expect(set.containsValid('a'));
    try testing.expect(!set.containsValid(0x0430));
    
    try testing.expect(set.containsConfused(0x0430));
    try testing.expect(!set.containsConfused('a'));
}

test "confusable data empty input" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var data = ConfusableData.init(allocator);
    defer data.deinit();
    
    const empty_cps = [_]CodePoint{};
    const is_confusable = try data.checkWholeScriptConfusables(&empty_cps, allocator);
    try testing.expect(!is_confusable);
}

test "confusable data single set safe" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var data = ConfusableData.init(allocator);
    defer data.deinit();
    
    // Create a test set
    data.sets = try allocator.alloc(ConfusableSet, 1);
    data.sets[0] = ConfusableSet.init(allocator, try allocator.dupe(u8, "latin"));
    
    var valid_test_data = try allocator.alloc(CodePoint, 2);
    valid_test_data[0] = 'a';
    valid_test_data[1] = 'b';
    data.sets[0].valid = valid_test_data;
    
    var confused_test_data = try allocator.alloc(CodePoint, 2);
    confused_test_data[0] = 0x0430;
    confused_test_data[1] = 0x0431;
    data.sets[0].confused = confused_test_data;
    
    // Test with only valid characters - should be safe
    const valid_only = [_]CodePoint{ 'a', 'b' };
    const is_confusable1 = try data.checkWholeScriptConfusables(&valid_only, allocator);
    try testing.expect(!is_confusable1);
    
    // Test with only confused characters - should be safe (single set)
    const confused_only = [_]CodePoint{ 0x0430, 0x0431 };
    const is_confusable2 = try data.checkWholeScriptConfusables(&confused_only, allocator);
    try testing.expect(!is_confusable2);
}