const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const input = "\u{200c}"; // ZERO WIDTH NON-JOINER
    std.debug.print("Testing tokenization of: {s} (hex: ", .{input});
    for (input) |byte| {
        std.debug.print("{x:0>2} ", .{byte});
    }
    std.debug.print(")\n", .{});

    const tokens = try ens.tokenize(allocator, input);
    defer allocator.free(tokens);

    std.debug.print("Got {} tokens\n", .{tokens.len});
    for (tokens, 0..) |token, i| {
        std.debug.print("Token {}: ", .{i});
        switch (token) {
            .emoji => |emoji| std.debug.print("Emoji: {s}\n", .{emoji}),
            .text => |text| std.debug.print("Text: {s}\n", .{text}),
        }
    }
}