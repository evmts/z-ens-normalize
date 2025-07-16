const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    std.debug.print("Starting emoji loading test...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Loading emoji data...\n", .{});
    const start_time = std.time.milliTimestamp();
    
    var emoji_map = try ens.static_data_loader.loadEmoji(allocator);
    defer emoji_map.deinit();
    
    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;
    
    std.debug.print("Emoji data loaded in {}ms\n", .{duration});
    std.debug.print("Total emojis: {}\n", .{emoji_map.all_emojis.items.len});
    std.debug.print("Max emoji length: {}\n", .{emoji_map.max_length});
    
    // Test a few known emojis
    const test_emojis = [_][]const u8{
        "😀",  // Basic emoji
        "👍",  // Thumbs up
        "❤️",  // Heart with FE0F
    };
    
    for (test_emojis) |emoji_str| {
        std.debug.print("\nTesting emoji: {s}\n", .{emoji_str});
        const match = emoji_map.findEmojiAt(allocator, emoji_str, 0);
        if (match) |m| {
            std.debug.print("  Found match at pos {} with length {}\n", .{m.pos, m.length});
        } else {
            std.debug.print("  No match found\n", .{});
        }
    }
    
    std.debug.print("\nTest complete\n", .{});
}