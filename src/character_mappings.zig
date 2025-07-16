const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const comptime_data = @import("comptime_data.zig");
const log = @import("logger.zig");

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
        log.trace("Getting mapping for U+{X:0>4}", .{cp});
        
        // Fast path for ASCII uppercase -> lowercase
        if (cp >= 'A' and cp <= 'Z') {
            // Use comptime-generated array for ASCII mappings
            const ascii_mappings = comptime blk: {
                var mappings: [26][1]CodePoint = undefined;
                for (0..26) |i| {
                    mappings[i] = [1]CodePoint{@as(CodePoint, 'a' + i)};
                }
                break :blk mappings;
            };
            const result = &ascii_mappings[cp - 'A'];
            log.trace("  ASCII uppercase U+{X:0>4} maps to U+{X:0>4}", .{cp, result[0]});
            return result;
        }
        
        // Check comptime mappings
        if (comptime_data.getMappedCodePoints(cp)) |mapped| {
            log.trace("  Found mapping: {} codepoints", .{mapped.len});
            return mapped;
        }
        
        log.trace("  No mapping found for U+{X:0>4}", .{cp});
        return null;
    }
    
    /// Check if a character is valid (no mapping needed)
    pub fn isValid(self: *const CharacterMappings, cp: CodePoint) bool {
        _ = self;
        const valid = comptime_data.isValid(cp);
        log.trace("Checking if U+{X:0>4} is valid: {}", .{cp, valid});
        return valid;
    }
    
    /// Check if a character should be ignored
    pub fn isIgnored(self: *const CharacterMappings, cp: CodePoint) bool {
        _ = self;
        const ignored = comptime_data.isIgnored(cp);
        log.trace("Checking if U+{X:0>4} should be ignored: {}", .{cp, ignored});
        return ignored;
    }
    
    /// Check if a character is fenced (placement restricted)
    pub fn isFenced(self: *const CharacterMappings, cp: CodePoint) bool {
        _ = self;
        const fenced = comptime_data.isFenced(cp);
        log.trace("Checking if U+{X:0>4} is fenced: {}", .{cp, fenced});
        return fenced;
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