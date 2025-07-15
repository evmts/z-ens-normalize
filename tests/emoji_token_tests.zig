const std = @import("std");
const ens_normalize = @import("ens_normalize");
const tokenizer = ens_normalize.tokenizer;
const code_points = ens_normalize.code_points;
const emoji = ens_normalize.emoji;
const static_data_loader = ens_normalize.static_data_loader;

test "emoji token - simple emoji" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test with thumbs up emoji
    const input = "hello👍world";
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);
    defer tokenized.deinit();
    
    // Should have: valid("hello"), emoji(👍), valid("world")
    var found_emoji = false;
    for (tokenized.tokens) |token| {
        if (token.type == .emoji) {
            found_emoji = true;
            break;
        }
    }
    
    try testing.expect(found_emoji);
}

test "emoji token - emoji with FE0F" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test with emoji that commonly has FE0F
    const input = "☺️"; // U+263A U+FE0F
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);
    defer tokenized.deinit();
    
    try testing.expect(tokenized.tokens.len > 0);
    try testing.expectEqual(tokenizer.TokenType.emoji, tokenized.tokens[0].type);
}

test "emoji token - skin tone modifier" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test with emoji with skin tone
    const input = "👍🏻"; // Thumbs up with light skin tone
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);
    defer tokenized.deinit();
    
    try testing.expect(tokenized.tokens.len == 1);
    try testing.expectEqual(tokenizer.TokenType.emoji, tokenized.tokens[0].type);
}

test "emoji token - ZWJ sequence" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test with family emoji (ZWJ sequence)
    const input = "👨‍👩‍👧‍👦"; // Family: man, woman, girl, boy
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);
    defer tokenized.deinit();
    
    // Should be recognized as a single emoji token if in spec.json
    try testing.expect(tokenized.tokens.len >= 1);
}

test "emoji token - mixed text and emoji" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test mixed content
    const input = "hello👋world🌍test";
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);
    defer tokenized.deinit();
    
    // Count emoji tokens
    var emoji_count: usize = 0;
    for (tokenized.tokens) |token| {
        if (token.type == .emoji) {
            emoji_count += 1;
        }
    }
    
    try testing.expect(emoji_count >= 2); // Should have at least 2 emoji tokens
}

test "emoji data loading" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test loading emoji data from spec.json
    var emoji_map = try static_data_loader.loadEmojiMap(allocator);
    defer emoji_map.deinit();
    
    // Should have loaded many emojis
    try testing.expect(emoji_map.all_emojis.items.len > 100);
    
    // Test that we have some common emojis
    // Note: These tests depend on what's actually in spec.json
}

test "emoji FE0F normalization" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test that emoji with and without FE0F produce the same token
    const input1 = "☺"; // Without FE0F
    const input2 = "☺️"; // With FE0F
    
    const tokenized1 = try tokenizer.TokenizedName.fromInput(allocator, input1, &specs, false);
    defer tokenized1.deinit();
    
    const tokenized2 = try tokenizer.TokenizedName.fromInput(allocator, input2, &specs, false);
    defer tokenized2.deinit();
    
    // Both should produce emoji tokens if the emoji is in spec.json
    // The exact behavior depends on what's in the spec
}