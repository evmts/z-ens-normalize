const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const specs = ens.code_points.CodePointsSpecs.init(allocator);
    
    // Test cases
    const test_cases = [_]struct {
        name: []const u8,
        input: []const u8,
    }{
        .{ .name = "empty", .input = "" },
        .{ .name = "simple_ascii", .input = "hello" },
        .{ .name = "with_stop", .input = "hello.world" },
        .{ .name = "uppercase", .input = "HELLO" },
        .{ .name = "numbers", .input = "123" },
        .{ .name = "underscore", .input = "hello_world" },
    };
    
    for (test_cases) |tc| {
        std.debug.print("\n=== Testing: {s} ===\n", .{tc.name});
        std.debug.print("Input: '{s}'\n", .{tc.input});
        
        const tokenized = ens.tokenizer.TokenizedName.fromInput(allocator, tc.input, &specs, false) catch |err| {
            std.debug.print("Error: {}\n", .{err});
            continue;
        };
        defer tokenized.deinit();
        
        std.debug.print("Tokens: {}\n", .{tokenized.tokens.len});
        for (tokenized.tokens, 0..) |token, i| {
            std.debug.print("  Token[{}]: type={s}", .{i, @tagName(token.type)});
            switch (token.type) {
                .valid => {
                    std.debug.print(", cps=[", .{});
                    for (token.data.valid.cps, 0..) |cp, j| {
                        if (j > 0) std.debug.print(", ", .{});
                        if (cp >= 32 and cp <= 126) {
                            std.debug.print("'{c}'", .{@as(u8, @intCast(cp))});
                        } else {
                            std.debug.print("U+{X:0>4}", .{cp});
                        }
                    }
                    std.debug.print("]", .{});
                },
                .mapped => {
                    std.debug.print(", cp=U+{X:0>4}, mapped=[", .{token.data.mapped.cp});
                    for (token.data.mapped.cps, 0..) |cp, j| {
                        if (j > 0) std.debug.print(", ", .{});
                        if (cp >= 32 and cp <= 126) {
                            std.debug.print("'{c}'", .{@as(u8, @intCast(cp))});
                        } else {
                            std.debug.print("U+{X:0>4}", .{cp});
                        }
                    }
                    std.debug.print("]", .{});
                },
                .stop => std.debug.print(", cp=U+{X:0>4}", .{token.data.stop.cp}),
                .disallowed => std.debug.print(", cp=U+{X:0>4}", .{token.data.disallowed.cp}),
                .ignored => std.debug.print(", cp=U+{X:0>4}", .{token.data.ignored.cp}),
                else => {},
            }
            std.debug.print("\n", .{});
        }
    }
}