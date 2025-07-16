const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    std.debug.print("Starting emoji load test...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("About to load emoji data...\n", .{});
    const start = std.time.milliTimestamp();
    
    var emoji_map = ens.emoji.EmojiMap.init(allocator);
    defer emoji_map.deinit();
    
    std.debug.print("EmojiMap initialized (empty)\n", .{});
    
    // Try adding just one emoji manually
    const test_emoji = [_]u32{0x1F600}; // 😀
    const test_emoji_fe0f = [_]u32{0x1F600, 0xFE0F}; // 😀️
    
    try emoji_map.addEmoji(&test_emoji, &test_emoji_fe0f);
    
    const end = std.time.milliTimestamp();
    std.debug.print("Added test emoji in {}ms\n", .{end - start});
    
    std.debug.print("Test complete\n", .{});
}