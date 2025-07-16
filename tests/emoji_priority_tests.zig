const std = @import("std");
const testing = std.testing;
const root = @import("ens_normalize");
const normalizer = root.normalizer;
const tokenizer = root.tokenizer;
const log = @import("ens_normalize").logger;

test "emoji should have highest priority - simple emoji case" {
    log.setLogLevel(.err); // Reduce noise in tests
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test simple emoji
    const input = "👍";
    const tokenized = try ens.tokenize(input);
    defer tokenized.deinit();
    
    try testing.expectEqual(@as(usize, 1), tokenized.tokens.len);
    try testing.expectEqual(tokenizer.TokenType.emoji, tokenized.tokens[0].type);
    try testing.expect(tokenized.tokens[0].isEmoji());
}

test "emoji priority over mapped characters" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Test emoji sequence that might overlap with mapped characters
    const input = "👨‍👩‍👧‍👦"; // Family emoji with ZWJ sequences
    const tokenized = try ens.tokenize(input);
    defer tokenized.deinit();
    
    try testing.expectEqual(@as(usize, 1), tokenized.tokens.len);
    try testing.expectEqual(tokenizer.TokenType.emoji, tokenized.tokens[0].type);
}

test "emoji priority - mixed text and emoji" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    const input = "hello👍world";
    const tokenized = try ens.tokenize(input);
    defer tokenized.deinit();
    
    // Should have 3 tokens: text, emoji, text
    try testing.expectEqual(@as(usize, 3), tokenized.tokens.len);
    try testing.expectEqual(tokenizer.TokenType.valid, tokenized.tokens[0].type);
    try testing.expectEqual(tokenizer.TokenType.emoji, tokenized.tokens[1].type);
    try testing.expectEqual(tokenizer.TokenType.valid, tokenized.tokens[2].type);
}

test "emoji priority - flag sequences" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // US flag emoji (regional indicators)
    const input = "🇺🇸";
    const tokenized = try ens.tokenize(input);
    defer tokenized.deinit();
    
    // Flag sequences should be treated as single emoji
    try testing.expectEqual(@as(usize, 1), tokenized.tokens.len);
    try testing.expectEqual(tokenizer.TokenType.emoji, tokenized.tokens[0].type);
}

test "emoji priority - skin tone modifiers" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Waving hand with skin tone modifier
    const input = "👋🏽";
    const tokenized = try ens.tokenize(input);
    defer tokenized.deinit();
    
    // Should be treated as single emoji
    try testing.expectEqual(@as(usize, 1), tokenized.tokens.len);
    try testing.expectEqual(tokenizer.TokenType.emoji, tokenized.tokens[0].type);
}

test "emoji priority - keycap sequences" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Keycap sequence "1️⃣"
    const input = "1\u{FE0F}\u{20E3}";
    const tokenized = try ens.tokenize(input);
    defer tokenized.deinit();
    
    // Should be treated as single emoji
    try testing.expectEqual(@as(usize, 1), tokenized.tokens.len);
    try testing.expectEqual(tokenizer.TokenType.emoji, tokenized.tokens[0].type);
}

test "emoji priority - FE0F variation selector" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Heart with FE0F (emoji presentation)
    const input = "❤️"; // U+2764 U+FE0F
    const tokenized = try ens.tokenize(input);
    defer tokenized.deinit();
    
    // Should be treated as emoji
    try testing.expectEqual(@as(usize, 1), tokenized.tokens.len);
    try testing.expectEqual(tokenizer.TokenType.emoji, tokenized.tokens[0].type);
}

test "emoji priority - text vs emoji presentation" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Digit "1" followed by combining enclosing keycap (without FE0F)
    const input_text = "1\u{20E3}"; // Text presentation
    const tokenized_text = try ens.tokenize(input_text);
    defer tokenized_text.deinit();
    
    // With FE0F, should be emoji
    const input_emoji = "1\u{FE0F}\u{20E3}"; // Emoji presentation
    const tokenized_emoji = try ens.tokenize(input_emoji);
    defer tokenized_emoji.deinit();
    
    // Both should be recognized as emoji sequences
    try testing.expectEqual(@as(usize, 1), tokenized_emoji.tokens.len);
    try testing.expectEqual(tokenizer.TokenType.emoji, tokenized_emoji.tokens[0].type);
}

test "emoji priority prevents splitting sequences" {
    log.setLogLevel(.err);
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    // Complex emoji sequence with multiple components
    const input = "👨‍👩‍👧"; // Family: man, woman, girl
    const tokenized = try ens.tokenize(input);
    defer tokenized.deinit();
    
    // Should not be split into individual components
    try testing.expectEqual(@as(usize, 1), tokenized.tokens.len);
    try testing.expectEqual(tokenizer.TokenType.emoji, tokenized.tokens[0].type);
    
    // Verify it contains the expected ZWJ sequences
    const emoji_token = tokenized.tokens[0];
    try testing.expect(emoji_token.emoji != null);
    
    // The emoji should have preserved the complete sequence
    const emoji_data = emoji_token.emoji.?;
    try testing.expect(emoji_data.emoji.len > 1); // Should have multiple codepoints
}