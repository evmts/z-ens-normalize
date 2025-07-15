const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;

pub const ParsedGroup = struct {
    name: []const u8,
    primary: std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage),
    secondary: std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage),
    primary_plus_secondary: std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage),
    cm_absent: bool,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8) ParsedGroup {
        return ParsedGroup{
            .name = name,
            .primary = std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage){},
            .secondary = std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage){},
            .primary_plus_secondary = std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage){},
            .cm_absent = true,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ParsedGroup) void {
        self.primary.deinit(self.allocator);
        self.secondary.deinit(self.allocator);
        self.primary_plus_secondary.deinit(self.allocator);
    }
    
    pub fn addPrimary(self: *ParsedGroup, cp: CodePoint) !void {
        try self.primary.put(self.allocator, cp, {});
        try self.primary_plus_secondary.put(self.allocator, cp, {});
    }
    
    pub fn addSecondary(self: *ParsedGroup, cp: CodePoint) !void {
        try self.secondary.put(self.allocator, cp, {});
        try self.primary_plus_secondary.put(self.allocator, cp, {});
    }
    
    pub fn containsCp(self: *const ParsedGroup, cp: CodePoint) bool {
        return self.primary_plus_secondary.contains(cp);
    }
    
    pub fn containsAllCps(self: *const ParsedGroup, cps: []const CodePoint) bool {
        for (cps) |cp| {
            if (!self.containsCp(cp)) {
                return false;
            }
        }
        return true;
    }
};

pub const ParsedWholeValue = union(enum) {
    number: u32,
    whole_object: ParsedWholeObject,
};

pub const ParsedWholeObject = struct {
    v: std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage),
    m: std.HashMapUnmanaged(CodePoint, []const []const u8, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ParsedWholeObject {
        return ParsedWholeObject{
            .v = std.HashMapUnmanaged(CodePoint, void, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage){},
            .m = std.HashMapUnmanaged(CodePoint, []const []const u8, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage){},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ParsedWholeObject) void {
        self.v.deinit(self.allocator);
        
        // Clean up the string arrays in m
        var iter = self.m.iterator();
        while (iter.next()) |entry| {
            for (entry.value_ptr.*) |str| {
                self.allocator.free(str);
            }
            self.allocator.free(entry.value_ptr.*);
        }
        self.m.deinit(self.allocator);
    }
};

pub const ParsedWholeMap = std.HashMapUnmanaged(CodePoint, ParsedWholeValue, std.hash_map.AutoContext(CodePoint), std.hash_map.default_max_load_percentage);

pub const CodePointsSpecs = struct {
    // This would contain the various mappings and data structures
    // needed for ENS normalization. For now, placeholder structure.
    allocator: std.mem.Allocator,
    groups: []ParsedGroup,
    whole_map: ParsedWholeMap,
    
    pub fn init(allocator: std.mem.Allocator) CodePointsSpecs {
        return CodePointsSpecs{
            .allocator = allocator,
            .groups = &[_]ParsedGroup{},
            .whole_map = ParsedWholeMap{},
        };
    }
    
    pub fn deinit(self: *CodePointsSpecs) void {
        for (self.groups) |*group| {
            group.deinit();
        }
        self.allocator.free(self.groups);
        
        var iter = self.whole_map.iterator();
        while (iter.next()) |entry| {
            switch (entry.value_ptr.*) {
                .whole_object => |*obj| obj.deinit(),
                .number => {},
            }
        }
        self.whole_map.deinit(self.allocator);
    }
    
    pub fn decompose(self: *const CodePointsSpecs, cp: CodePoint) ?[]const CodePoint {
        // Placeholder for decomposition logic
        _ = self;
        _ = cp;
        return null;
    }
};

test "ParsedGroup basic operations" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var group = ParsedGroup.init(allocator, "Test");
    defer group.deinit();
    
    try group.addPrimary(0x41); // 'A'
    try group.addSecondary(0x42); // 'B'
    
    try testing.expect(group.containsCp(0x41));
    try testing.expect(group.containsCp(0x42));
    try testing.expect(!group.containsCp(0x43));
    
    const cps = [_]CodePoint{ 0x41, 0x42 };
    try testing.expect(group.containsAllCps(&cps));
    
    const cps_with_missing = [_]CodePoint{ 0x41, 0x43 };
    try testing.expect(!group.containsAllCps(&cps_with_missing));
}