const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Set log level to debug
    ens.logger.setLogLevel(.debug);
    
    var normalizer = try ens.normalizer.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    std.debug.print("Testing emoji priority...\n", .{});
    
    // Test simple emoji
    const input = "👍";
    std.debug.print("Input: {s}\n", .{input});
    
    const tokenized = try normalizer.tokenize(input);
    defer tokenized.deinit();
    
    std.debug.print("Tokens: {}\n", .{tokenized.tokens.len});
    if (tokenized.tokens.len > 0) {
        const token = tokenized.tokens[0];
        std.debug.print("Token type: {s}\n", .{@tagName(token.type)});
        std.debug.print("Is emoji: {}\n", .{token.isEmoji()});
    }
}