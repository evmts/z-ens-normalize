const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const utils = @import("utils.zig");

/// Single emoji sequence data
pub const EmojiData = struct {
    /// Canonical form with FE0F
    emoji: []const CodePoint,
    /// Form without FE0F for matching
    no_fe0f: []const CodePoint,
    
    pub fn deinit(self: EmojiData, allocator: std.mem.Allocator) void {
        allocator.free(self.emoji);
        allocator.free(self.no_fe0f);
    }
};

/// Map for efficient emoji lookup
pub const EmojiMap = struct {
    /// Map from no_fe0f codepoint sequence to emoji data
    /// Using string key for simpler lookup
    emojis: std.StringHashMap(EmojiData),
    /// Maximum emoji sequence length (for optimization)
    max_length: usize,
    /// All emoji sequences for building regex pattern
    all_emojis: std.ArrayList(EmojiData),
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) EmojiMap {
        return EmojiMap{
            .emojis = std.StringHashMap(EmojiData).init(allocator),
            .max_length = 0,
            .all_emojis = std.ArrayList(EmojiData).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *EmojiMap) void {
        // Free all emoji data
        for (self.all_emojis.items) |emoji_data| {
            emoji_data.deinit(self.allocator);
        }
        self.all_emojis.deinit();
        
        // Free all keys in the map
        var iter = self.emojis.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.emojis.deinit();
    }
    
    /// Add an emoji sequence to the map
    pub fn addEmoji(self: *EmojiMap, no_fe0f: []const CodePoint, canonical: []const CodePoint) !void {
        // Create owned copies
        const owned_no_fe0f = try self.allocator.dupe(CodePoint, no_fe0f);
        errdefer self.allocator.free(owned_no_fe0f);
        
        const owned_canonical = try self.allocator.dupe(CodePoint, canonical);
        errdefer self.allocator.free(owned_canonical);
        
        const emoji_data = EmojiData{
            .emoji = owned_canonical,
            .no_fe0f = owned_no_fe0f,
        };
        
        // Convert no_fe0f to string key
        const key = try utils.cps2str(self.allocator, no_fe0f);
        defer self.allocator.free(key);
        
        // Add to map with owned key
        const owned_key = try self.allocator.dupe(u8, key);
        try self.emojis.put(owned_key, emoji_data);
        
        // Add to all emojis list
        try self.all_emojis.append(emoji_data);
        
        // Update max length
        const len = std.unicode.utf8CountCodepoints(key) catch key.len;
        if (len > self.max_length) {
            self.max_length = len;
        }
    }
    
    /// Find emoji at given position in string
    pub fn findEmojiAt(self: *const EmojiMap, allocator: std.mem.Allocator, input: []const u8, pos: usize) ?EmojiMatch {
        if (pos >= input.len) return null;
        
        // Try from longest possible match down to single character
        var len = @min(input.len - pos, self.max_length * 4); // rough estimate for max UTF-8 bytes
        
        while (len > 0) : (len -= 1) {
            if (pos + len > input.len) continue;
            
            const slice = input[pos..pos + len];
            
            // Check if this is a valid UTF-8 boundary
            if (len < input.len - pos and !std.unicode.utf8ValidateSlice(slice)) {
                continue;
            }
            
            // Convert to codepoints and remove FE0F
            const cps = utils.str2cps(allocator, slice) catch continue;
            defer allocator.free(cps);
            
            const no_fe0f = utils.filterFe0f(allocator, cps) catch continue;
            defer allocator.free(no_fe0f);
            
            // Convert to string key
            const key = utils.cps2str(allocator, no_fe0f) catch continue;
            defer allocator.free(key);
            
            // Look up in map
            if (self.emojis.get(key)) |emoji_data| {
                // Need to return owned copies since we're deferring the frees
                const owned_cps = allocator.dupe(CodePoint, cps) catch continue;
                return EmojiMatch{
                    .emoji_data = emoji_data,
                    .input = slice,
                    .cps_input = owned_cps,
                    .byte_len = len,
                };
            }
        }
        
        return null;
    }
};

/// Result of emoji matching
pub const EmojiMatch = struct {
    emoji_data: EmojiData,
    input: []const u8,
    cps_input: []const CodePoint,
    byte_len: usize,
};

/// Remove FE0F (variation selector) from codepoint sequence
pub fn filterFE0F(allocator: std.mem.Allocator, cps: []const CodePoint) ![]CodePoint {
    return utils.filterFe0f(allocator, cps);
}

test "emoji map basic operations" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var emoji_map = EmojiMap.init(allocator);
    defer emoji_map.deinit();
    
    // Add simple emoji
    const smile_no_fe0f = [_]CodePoint{0x263A}; // ☺
    const smile_canonical = [_]CodePoint{0x263A, 0xFE0F}; // ☺️
    try emoji_map.addEmoji(&smile_no_fe0f, &smile_canonical);
    
    // Test lookup
    const key = try utils.cps2str(allocator, &smile_no_fe0f);
    defer allocator.free(key);
    
    const found = emoji_map.emojis.get(key);
    try testing.expect(found != null);
    try testing.expectEqualSlices(CodePoint, &smile_canonical, found.?.emoji);
}

test "emoji map population - incorrect way" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var emoji_map = EmojiMap.init(allocator);
    defer emoji_map.deinit();
    
    // Create emoji data
    const thumbs_emoji = try allocator.alloc(CodePoint, 1);
    thumbs_emoji[0] = 0x1F44D;
    const thumbs_no_fe0f = try allocator.dupe(CodePoint, thumbs_emoji);
    
    const emoji_data = EmojiData{
        .emoji = thumbs_emoji,
        .no_fe0f = thumbs_no_fe0f,
    };
    
    // Add to all_emojis (what our loader does)
    try emoji_map.all_emojis.append(emoji_data);
    
    // But this doesn't populate the hash map!
    // Let's verify the hash map is empty
    const key = try utils.cps2str(allocator, thumbs_no_fe0f);
    defer allocator.free(key);
    
    const found = emoji_map.emojis.get(key);
    try testing.expect(found == null); // This should pass, showing the bug
    
    // Now test findEmojiAt - it should fail to find the emoji
    const input = "Hello 👍 World";
    const match = emoji_map.findEmojiAt(allocator, input, 6);
    try testing.expect(match == null); // This should pass, confirming the bug
}

test "emoji map population - correct way" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var emoji_map = EmojiMap.init(allocator);
    defer emoji_map.deinit();
    
    // Use addEmoji which populates both structures
    const thumbs_no_fe0f = [_]CodePoint{0x1F44D};
    const thumbs_emoji = [_]CodePoint{0x1F44D};
    try emoji_map.addEmoji(&thumbs_no_fe0f, &thumbs_emoji);
    
    // Verify the hash map is populated
    const key = try utils.cps2str(allocator, &thumbs_no_fe0f);
    defer allocator.free(key);
    
    const found = emoji_map.emojis.get(key);
    try testing.expect(found != null);
    
    // Now test findEmojiAt - it should find the emoji
    const input = "Hello 👍 World";
    const match = emoji_map.findEmojiAt(allocator, input, 6);
    try testing.expect(match != null);
    if (match) |m| {
        defer allocator.free(m.cps_input);
        try testing.expectEqualSlices(CodePoint, &thumbs_emoji, m.emoji_data.emoji);
    }
}

test "emoji matching" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var emoji_map = EmojiMap.init(allocator);
    defer emoji_map.deinit();
    
    // Add thumbs up emoji
    const thumbs_no_fe0f = [_]CodePoint{0x1F44D}; // 👍
    const thumbs_canonical = [_]CodePoint{0x1F44D};
    try emoji_map.addEmoji(&thumbs_no_fe0f, &thumbs_canonical);
    
    // Test finding emoji in string
    const input = "Hello 👍 World";
    const match = emoji_map.findEmojiAt(allocator, input, 6); // Position of 👍
    
    try testing.expect(match != null);
    if (match) |m| {
        defer allocator.free(m.cps_input);
        try testing.expectEqualSlices(CodePoint, &thumbs_canonical, m.emoji_data.emoji);
    }
}