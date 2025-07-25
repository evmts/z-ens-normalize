const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const comptime_data = @import("comptime_data.zig");

/// Character mapping system for ENS normalization using comptime data
pub const CharacterMappings = struct {
    // We don't need any runtime storage anymore!
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !CharacterMappings {
        return CharacterMappings{
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *CharacterMappings) void {
        _ = self;
        // Nothing to clean up - all data is comptime!
    }
    
    /// Get the mapped characters for a given code point
    /// Returns null if no mapping exists
    pub fn getMapped(self: *const CharacterMappings, cp: CodePoint) ?[]const CodePoint {
        _ = self;
        // Fast path for ASCII uppercase -> lowercase
        if (cp >= 'A' and cp <= 'Z') {
            // Return a slice to a static array
            const lowercase = [1]CodePoint{cp + 32};
            return &lowercase;
        }
        
        // Check comptime mappings
        return comptime_data.getMappedCodePoints(cp);
    }
    
    /// Check if a character is valid (no mapping needed)
    pub fn isValid(self: *const CharacterMappings, cp: CodePoint) bool {
        _ = self;
        return comptime_data.isValid(cp);
    }
    
    /// Check if a character should be ignored
    pub fn isIgnored(self: *const CharacterMappings, cp: CodePoint) bool {
        _ = self;
        return comptime_data.isIgnored(cp);
    }
    
    /// Check if a character is fenced (placement restricted)
    pub fn isFenced(self: *const CharacterMappings, cp: CodePoint) bool {
        _ = self;
        return comptime_data.isFenced(cp);
    }
    
    // These methods are no longer needed since we use comptime data
    pub fn addMapping(self: *CharacterMappings, from: CodePoint, to: []const CodePoint) !void {
        _ = self;
        _ = from;
        _ = to;
        @panic("Cannot add mappings at runtime - use comptime data");
    }
    
    pub fn addValid(self: *CharacterMappings, cp: CodePoint) !void {
        _ = self;
        _ = cp;
        @panic("Cannot add valid chars at runtime - use comptime data");
    }
    
    pub fn addIgnored(self: *CharacterMappings, cp: CodePoint) !void {
        _ = self;
        _ = cp;
        @panic("Cannot add ignored chars at runtime - use comptime data");
    }
};

/// Create character mappings - now just returns an empty struct
pub fn createWithUnicodeMappings(allocator: std.mem.Allocator) !CharacterMappings {
    return CharacterMappings.init(allocator);
}

// Tests
test "CharacterMappings - ASCII case folding" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var mappings = try CharacterMappings.init(allocator);
    defer mappings.deinit();
    
    // Test uppercase -> lowercase mapping
    const mapped_A = mappings.getMapped('A');
    try testing.expect(mapped_A != null);
    try testing.expectEqual(@as(CodePoint, 'a'), mapped_A.?[0]);
    
    const mapped_Z = mappings.getMapped('Z');
    try testing.expect(mapped_Z != null);
    try testing.expectEqual(@as(CodePoint, 'z'), mapped_Z.?[0]);
    
    // Test lowercase has no mapping
    const mapped_a = mappings.getMapped('a');
    try testing.expect(mapped_a == null);
    
    // Test valid characters
    try testing.expect(mappings.isValid('a'));
    try testing.expect(mappings.isValid('z'));
    try testing.expect(mappings.isValid('0'));
    try testing.expect(mappings.isValid('9'));
}

test "CharacterMappings - comptime data access" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var mappings = try CharacterMappings.init(allocator);
    defer mappings.deinit();
    
    // Test that we can access comptime data
    if (comptime_data.character_mappings.len > 0) {
        const first = comptime_data.character_mappings[0];
        const result = mappings.getMapped(first.from);
        try testing.expect(result != null);
        try testing.expectEqualSlices(CodePoint, first.to, result.?);
    }
}