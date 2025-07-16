const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("\n=== Testing Zero Width Non-Joiner (U+200C) ===\n", .{});
    
    const input = "\u{200C}";
    const specs = ens.code_points.CodePointsSpecs.init(allocator);
    
    const tokenized = try ens.tokenizer.TokenizedName.fromInput(allocator, input, &specs, false);
    defer tokenized.deinit();
    
    std.debug.print("Input: '{s}' (hex: ", .{input});
    for (input) |byte| {
        std.debug.print("{x:0>2} ", .{byte});
    }
    std.debug.print(")\n", .{});
    
    std.debug.print("Tokens produced: {}\n", .{tokenized.tokens.len});
    
    for (tokenized.tokens, 0..) |token, i| {
        std.debug.print("Token {}: type={s}\n", .{i, @tagName(token.type)});
        switch (token.type) {
            .disallowed => {
                std.debug.print("  Disallowed codepoint: U+{X:0>4}\n", .{token.data.disallowed.cp});
            },
            else => {},
        }
    }
}