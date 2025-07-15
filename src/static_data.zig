const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;

// This module would contain the static data structures and JSON parsing
// For now, it's a placeholder that would need to be implemented with
// the actual ENS normalization data

pub const SpecJson = struct {
    pub const GroupName = union(enum) {
        ascii,
        emoji,
        greek,
        other: []const u8,
    };
    
    pub const Group = struct {
        name: GroupName,
        primary: []const CodePoint,
        secondary: []const CodePoint,
        cm: []const CodePoint,
    };
    
    pub const WholeValue = union(enum) {
        number: u32,
        whole_object: WholeObject,
    };
    
    pub const WholeObject = struct {
        v: []const CodePoint,
        m: std.StringHashMap([]const []const u8),
    };
    
    pub const NfJson = struct {
        // Normalization data structures would go here
        // For now, placeholder
    };
};

// Placeholder functions that would load and parse the actual JSON data
pub fn loadSpecData(allocator: std.mem.Allocator) !SpecJson {
    _ = allocator;
    // This would load from spec.json
    return SpecJson{};
}

pub fn loadNfData(allocator: std.mem.Allocator) !SpecJson.NfJson {
    _ = allocator;
    // This would load from nf.json
    return SpecJson.NfJson{};
}

test "static_data placeholder" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const spec = try loadSpecData(allocator);
    _ = spec;
    
    const nf = try loadNfData(allocator);
    _ = nf;
}