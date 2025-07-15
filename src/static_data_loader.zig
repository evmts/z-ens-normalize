const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const character_mappings = @import("character_mappings.zig");
const CharacterMappings = character_mappings.CharacterMappings;
const nfc = @import("nfc.zig");
const emoji = @import("emoji.zig");
const script_groups = @import("script_groups.zig");
const confusables = @import("confusables.zig");
const zon_loader = @import("zon_data_loader.zig");

/// Load character mappings from ZON data
pub fn loadCharacterMappings(allocator: std.mem.Allocator) !CharacterMappings {
    return zon_loader.loadCharacterMappings(allocator);
}

/// Load NFC data from ZON
pub fn loadNFC(allocator: std.mem.Allocator) !nfc.NFCData {
    return zon_loader.loadNFC(allocator);
}

/// Load emoji data from ZON
pub fn loadEmoji(allocator: std.mem.Allocator) !emoji.EmojiData {
    return zon_loader.loadEmoji(allocator);
}

/// Load script groups from ZON
pub fn loadScriptGroups(allocator: std.mem.Allocator) !script_groups.ScriptGroups {
    return zon_loader.loadScriptGroups(allocator);
}

/// Load confusable data from ZON
pub fn loadConfusables(allocator: std.mem.Allocator) !confusables.ConfusableData {
    return zon_loader.loadConfusables(allocator);
}

test "static data loading from ZON" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test character mappings loading
    var mappings = loadCharacterMappings(allocator) catch |err| {
        std.debug.print("Failed to load character mappings: {}\n", .{err});
        return;
    };
    defer mappings.deinit();
    
    try testing.expect(mappings.unicode_mappings.count() > 0);
    try testing.expect(mappings.valid_chars.count() > 0);
    try testing.expect(mappings.ignored_chars.count() > 0);
    try testing.expect(mappings.fenced_chars.count() > 0);

    // Test script groups loading
    var groups = loadScriptGroups(allocator) catch |err| {
        std.debug.print("Failed to load script groups: {}\n", .{err});
        return;
    };
    defer groups.deinit();
    
    try testing.expect(groups.groups.len > 0);
    try testing.expect(groups.nsm_set.count() > 0);
    try testing.expectEqual(@as(usize, 4), groups.nsm_max);
    
    // Test confusables loading
    var confusable_data = loadConfusables(allocator) catch |err| {
        std.debug.print("Failed to load confusables: {}\n", .{err});
        return;
    };
    defer confusable_data.deinit();
    
    try testing.expect(confusable_data.sets.len > 0);
    
    std.debug.print("✓ Successfully loaded ZON data with confusables\n", .{});
}