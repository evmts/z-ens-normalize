const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    ens.logger.setLogLevel(.debug);
    
    var normalizer = try ens.normalizer.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    // Test 1: Simple emoji
    {
        const input = "👍";
        std.debug.print("\nTest 1: Simple emoji '{}'\n", .{input});
        
        const tokenized = try normalizer.tokenize(input);
        defer tokenized.deinit();
        
        std.debug.print("  Tokens: {}\n", .{tokenized.tokens.len});
        if (tokenized.tokens.len > 0) {
            std.debug.print("  Token[0] type: {s}\n", .{@tagName(tokenized.tokens[0].type)});
            std.debug.print("  Is emoji: {}\n", .{tokenized.tokens[0].isEmoji()});
        }
    }
    
    // Test 2: Mixed text and emoji
    {
        const input = "hello👍world";
        std.debug.print("\nTest 2: Mixed text and emoji '{s}'\n", .{input});
        
        const tokenized = try normalizer.tokenize(input);
        defer tokenized.deinit();
        
        std.debug.print("  Tokens: {}\n", .{tokenized.tokens.len});
        for (tokenized.tokens, 0..) |token, i| {
            std.debug.print("  Token[{}] type: {s}, isEmoji: {}\n", .{i, @tagName(token.type), token.isEmoji()});
        }
    }
    
    // Test 3: Complex emoji sequence (family)
    {
        const input = "👨‍👩‍👧‍👦"; // Family emoji
        std.debug.print("\nTest 3: Family emoji\n", .{});
        
        const tokenized = try normalizer.tokenize(input);
        defer tokenized.deinit();
        
        std.debug.print("  Tokens: {}\n", .{tokenized.tokens.len});
        if (tokenized.tokens.len > 0) {
            std.debug.print("  Token[0] type: {s}\n", .{@tagName(tokenized.tokens[0].type)});
            std.debug.print("  Is emoji: {}\n", .{tokenized.tokens[0].isEmoji()});
            if (tokenized.tokens[0].emoji) |emoji_data| {
                std.debug.print("  Emoji codepoints: {}\n", .{emoji_data.emoji.len});
            }
        }
    }
}