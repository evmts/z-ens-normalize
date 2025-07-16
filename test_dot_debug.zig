const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Enable debug logging to see what's happening
    ens.logger.setLogLevel(.debug);
    
    var normalizer = try ens.normalizer.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    const input = "hello.eth";
    std.debug.print("\n=== Tokenizing '{s}' ===\n", .{input});
    
    const tokenized = try normalizer.tokenize(input);
    defer tokenized.deinit();
    
    std.debug.print("Total tokens: {}\n", .{tokenized.tokens.len});
    for (tokenized.tokens, 0..) |token, i| {
        std.debug.print("Token[{}]: type={s}, codepoints.len={}\n", .{i, @tagName(token.type), token.codepoints.len});
        if (token.type == .stop) {
            std.debug.print("  -> STOP token found!\n", .{});
        }
    }
}