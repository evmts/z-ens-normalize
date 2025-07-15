const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;

/// Character mapping system for ENS normalization
/// Handles ASCII case folding and Unicode character mappings
pub const CharacterMappings = struct {
    // ASCII case folding map (A-Z -> a-z)
    ascii_case_map: [26]CodePoint,
    
    // Storage for ASCII case folding results
    ascii_case_results: [26][1]CodePoint,
    
    // Unicode character mappings (HashMap: CodePoint -> []CodePoint)
    unicode_mappings: std.AutoHashMap(CodePoint, []const CodePoint),
    
    // Set of valid characters (no mapping needed)
    valid_chars: std.AutoHashMap(CodePoint, void),
    
    // Set of ignored characters (removed from output)
    ignored_chars: std.AutoHashMap(CodePoint, void),
    
    // Set of fenced characters (placement restricted)
    fenced_chars: std.AutoHashMap(CodePoint, void),
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !CharacterMappings {
        const case_map = initASCIICaseMap();
        var case_results: [26][1]CodePoint = undefined;
        for (0..26) |i| {
            case_results[i] = [1]CodePoint{case_map[i]};
        }
        
        var mappings = CharacterMappings{
            .ascii_case_map = case_map,
            .ascii_case_results = case_results,
            .unicode_mappings = std.AutoHashMap(CodePoint, []const CodePoint).init(allocator),
            .valid_chars = std.AutoHashMap(CodePoint, void).init(allocator),
            .ignored_chars = std.AutoHashMap(CodePoint, void).init(allocator),
            .fenced_chars = std.AutoHashMap(CodePoint, void).init(allocator),
            .allocator = allocator,
        };
        
        // Initialize with basic ASCII lowercase letters and digits
        try mappings.initBasicValid();
        
        // Initialize with basic ignored characters
        try mappings.initBasicIgnored();
        
        return mappings;
    }
    
    pub fn deinit(self: *CharacterMappings) void {
        // Clean up unicode mappings
        var iterator = self.unicode_mappings.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.unicode_mappings.deinit();
        self.valid_chars.deinit();
        self.ignored_chars.deinit();
        self.fenced_chars.deinit();
    }
    
    /// Get the mapped characters for a given code point
    /// Returns null if no mapping exists
    pub fn getMapped(self: *const CharacterMappings, cp: CodePoint) ?[]const CodePoint {
        // Fast path for ASCII uppercase -> lowercase
        if (cp >= 'A' and cp <= 'Z') {
            const index = cp - 'A';
            return &self.ascii_case_results[index];
        }
        
        // Check Unicode mappings
        return self.unicode_mappings.get(cp);
    }
    
    /// Check if a character is valid (no mapping needed)
    pub fn isValid(self: *const CharacterMappings, cp: CodePoint) bool {
        return self.valid_chars.contains(cp);
    }
    
    /// Check if a character should be ignored
    pub fn isIgnored(self: *const CharacterMappings, cp: CodePoint) bool {
        return self.ignored_chars.contains(cp);
    }
    
    /// Check if a character is fenced (placement restricted)
    pub fn isFenced(self: *const CharacterMappings, cp: CodePoint) bool {
        return self.fenced_chars.contains(cp);
    }
    
    /// Add a Unicode character mapping
    pub fn addMapping(self: *CharacterMappings, from: CodePoint, to: []const CodePoint) !void {
        const owned_mapping = try self.allocator.dupe(CodePoint, to);
        try self.unicode_mappings.put(from, owned_mapping);
    }
    
    /// Add a valid character
    pub fn addValid(self: *CharacterMappings, cp: CodePoint) !void {
        try self.valid_chars.put(cp, {});
    }
    
    /// Add an ignored character
    pub fn addIgnored(self: *CharacterMappings, cp: CodePoint) !void {
        try self.ignored_chars.put(cp, {});
    }
    
    /// Initialize ASCII case mapping (A-Z -> a-z)
    fn initASCIICaseMap() [26]CodePoint {
        var map: [26]CodePoint = undefined;
        for (0..26) |i| {
            map[i] = @as(CodePoint, @intCast('a' + i));
        }
        return map;
    }
    
    /// Initialize basic valid characters (a-z, 0-9, -, _, ')
    fn initBasicValid(self: *CharacterMappings) !void {
        // ASCII lowercase letters
        for ('a'..('z' + 1)) |c| {
            try self.addValid(@as(CodePoint, @intCast(c)));
        }
        
        // ASCII digits
        for ('0'..('9' + 1)) |c| {
            try self.addValid(@as(CodePoint, @intCast(c)));
        }
        
        // Special characters
        try self.addValid('-');  // hyphen
        try self.addValid('_');  // underscore
        try self.addValid('\''); // apostrophe
    }
    
    /// Initialize basic ignored characters
    fn initBasicIgnored(self: *CharacterMappings) !void {
        try self.addIgnored(0x00AD); // soft hyphen
        try self.addIgnored(0x200C); // zero width non-joiner
        try self.addIgnored(0x200D); // zero width joiner
        try self.addIgnored(0xFEFF); // zero width no-break space
    }
};

/// Create character mappings with common Unicode mappings
pub fn createWithUnicodeMappings(allocator: std.mem.Allocator) !CharacterMappings {
    var mappings = try CharacterMappings.init(allocator);
    errdefer mappings.deinit();
    
    // Add common Unicode character mappings
    try addCommonUnicodeMappings(&mappings);
    
    return mappings;
}

/// Add common Unicode character mappings
fn addCommonUnicodeMappings(mappings: *CharacterMappings) !void {
    // Mathematical symbols - ALL map directly to lowercase per reference spec.zon
    try mappings.addMapping(0x2102, &[_]CodePoint{0x0063}); // ℂ -> c
    try mappings.addMapping(0x210A, &[_]CodePoint{0x0067}); // ℊ -> g  
    try mappings.addMapping(0x210B, &[_]CodePoint{0x0068}); // ℋ -> h
    try mappings.addMapping(0x210C, &[_]CodePoint{0x0068}); // ℌ -> h
    try mappings.addMapping(0x210D, &[_]CodePoint{0x0068}); // ℍ -> h
    try mappings.addMapping(0x210E, &[_]CodePoint{0x0068}); // ℎ -> h
    try mappings.addMapping(0x2110, &[_]CodePoint{0x0069}); // ℐ -> i
    try mappings.addMapping(0x2111, &[_]CodePoint{0x0069}); // ℑ -> i
    try mappings.addMapping(0x2112, &[_]CodePoint{0x006C}); // ℒ -> l
    try mappings.addMapping(0x2113, &[_]CodePoint{0x006C}); // ℓ -> l
    try mappings.addMapping(0x2115, &[_]CodePoint{0x006E}); // ℕ -> n
    try mappings.addMapping(0x2116, &[_]CodePoint{0x006E, 0x006F}); // № -> no
    try mappings.addMapping(0x2119, &[_]CodePoint{0x0070}); // ℙ -> p
    try mappings.addMapping(0x211A, &[_]CodePoint{0x0071}); // ℚ -> q
    try mappings.addMapping(0x211B, &[_]CodePoint{0x0072}); // ℛ -> r
    try mappings.addMapping(0x211C, &[_]CodePoint{0x0072}); // ℜ -> r
    try mappings.addMapping(0x211D, &[_]CodePoint{0x0072}); // ℝ -> r
    try mappings.addMapping(0x2124, &[_]CodePoint{0x007A}); // ℤ -> z
    try mappings.addMapping(0x2128, &[_]CodePoint{0x007A}); // ℨ -> z
    try mappings.addMapping(0x212A, &[_]CodePoint{0x006B}); // K -> k
    try mappings.addMapping(0x212B, &[_]CodePoint{0x00E5}); // Å -> å
    try mappings.addMapping(0x212C, &[_]CodePoint{0x0062}); // ℬ -> b
    try mappings.addMapping(0x212D, &[_]CodePoint{0x0063}); // ℭ -> c
    try mappings.addMapping(0x212F, &[_]CodePoint{0x0065}); // ℯ -> e (already correct)
    try mappings.addMapping(0x2130, &[_]CodePoint{0x0065}); // ℰ -> e
    try mappings.addMapping(0x2131, &[_]CodePoint{0x0066}); // ℱ -> f
    try mappings.addMapping(0x2133, &[_]CodePoint{0x006D}); // ℳ -> m
    try mappings.addMapping(0x2134, &[_]CodePoint{0x006F}); // ℴ -> o (already correct)
    
    // Fractions
    try mappings.addMapping(0x00BD, &[_]CodePoint{0x0031, 0x2044, 0x0032}); // ½ -> 1⁄2
    try mappings.addMapping(0x2153, &[_]CodePoint{0x0031, 0x2044, 0x0033}); // ⅓ -> 1⁄3
    try mappings.addMapping(0x2154, &[_]CodePoint{0x0032, 0x2044, 0x0033}); // ⅔ -> 2⁄3
    try mappings.addMapping(0x00BC, &[_]CodePoint{0x0031, 0x2044, 0x0034}); // ¼ -> 1⁄4
    try mappings.addMapping(0x00BE, &[_]CodePoint{0x0033, 0x2044, 0x0034}); // ¾ -> 3⁄4
    try mappings.addMapping(0x2155, &[_]CodePoint{0x0031, 0x2044, 0x0035}); // ⅕ -> 1⁄5
    try mappings.addMapping(0x2156, &[_]CodePoint{0x0032, 0x2044, 0x0035}); // ⅖ -> 2⁄5
    try mappings.addMapping(0x2157, &[_]CodePoint{0x0033, 0x2044, 0x0035}); // ⅗ -> 3⁄5
    try mappings.addMapping(0x2158, &[_]CodePoint{0x0034, 0x2044, 0x0035}); // ⅘ -> 4⁄5
    try mappings.addMapping(0x2159, &[_]CodePoint{0x0031, 0x2044, 0x0036}); // ⅙ -> 1⁄6
    try mappings.addMapping(0x215A, &[_]CodePoint{0x0035, 0x2044, 0x0036}); // ⅚ -> 5⁄6
    try mappings.addMapping(0x215B, &[_]CodePoint{0x0031, 0x2044, 0x0038}); // ⅛ -> 1⁄8
    try mappings.addMapping(0x215C, &[_]CodePoint{0x0033, 0x2044, 0x0038}); // ⅜ -> 3⁄8
    try mappings.addMapping(0x215D, &[_]CodePoint{0x0035, 0x2044, 0x0038}); // ⅝ -> 5⁄8
    try mappings.addMapping(0x215E, &[_]CodePoint{0x0037, 0x2044, 0x0038}); // ⅞ -> 7⁄8
    
    // Special characters
    try mappings.addMapping(0x2116, &[_]CodePoint{0x004E, 0x006F}); // № -> No
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
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{'a'}, mapped_A.?);
    
    const mapped_Z = mappings.getMapped('Z');
    try testing.expect(mapped_Z != null);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{'z'}, mapped_Z.?);
    
    // Test lowercase has no mapping
    const mapped_a = mappings.getMapped('a');
    try testing.expect(mapped_a == null);
    
    // Test valid characters
    try testing.expect(mappings.isValid('a'));
    try testing.expect(mappings.isValid('z'));
    try testing.expect(mappings.isValid('0'));
    try testing.expect(mappings.isValid('9'));
    try testing.expect(mappings.isValid('-'));
    try testing.expect(mappings.isValid('_'));
    try testing.expect(mappings.isValid('\''));
    
    // Test ignored characters
    try testing.expect(mappings.isIgnored(0x00AD)); // soft hyphen
    try testing.expect(mappings.isIgnored(0x200C)); // ZWNJ
    try testing.expect(mappings.isIgnored(0x200D)); // ZWJ
}

test "CharacterMappings - Unicode mappings" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var mappings = try createWithUnicodeMappings(allocator);
    defer mappings.deinit();
    
    // Test mathematical symbols
    const mapped_H = mappings.getMapped(0x210C); // ℌ
    try testing.expect(mapped_H != null);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{'h'}, mapped_H.?);
    
    const mapped_l = mappings.getMapped(0x2113); // ℓ
    try testing.expect(mapped_l != null);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{'l'}, mapped_l.?);
    
    // Test fractions
    const mapped_half = mappings.getMapped(0x00BD); // ½
    try testing.expect(mapped_half != null);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{'1', 0x2044, '2'}, mapped_half.?);
    
    const mapped_third = mappings.getMapped(0x2153); // ⅓
    try testing.expect(mapped_third != null);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{'1', 0x2044, '3'}, mapped_third.?);
    
    // Test special characters
    const mapped_no = mappings.getMapped(0x2116); // №
    try testing.expect(mapped_no != null);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{'N', 'o'}, mapped_no.?);
}

test "CharacterMappings - memory management" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test creation and cleanup
    var mappings = try CharacterMappings.init(allocator);
    defer mappings.deinit();
    
    // Add custom mapping
    try mappings.addMapping(0x1234, &[_]CodePoint{0x5678, 0x9ABC});
    
    // Verify mapping was added
    const mapped = mappings.getMapped(0x1234);
    try testing.expect(mapped != null);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{0x5678, 0x9ABC}, mapped.?);
    
    // Test adding valid and ignored characters
    try mappings.addValid(0x1111);
    try mappings.addIgnored(0x2222);
    
    try testing.expect(mappings.isValid(0x1111));
    try testing.expect(mappings.isIgnored(0x2222));
}