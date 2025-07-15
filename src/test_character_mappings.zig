const std = @import("std");
const root = @import("root.zig");
const tokenizer = @import("tokenizer.zig");
const character_mappings = @import("character_mappings.zig");
const static_data_loader = @import("static_data_loader.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("Character Mappings Test\n", .{});
    try stdout.print("======================\n\n", .{});
    
    // Test cases that should demonstrate character mappings
    const test_cases = [_]struct { input: []const u8, expected: []const u8 }{
        .{ .input = "HELLO", .expected = "hello" },
        .{ .input = "Hello", .expected = "hello" },
        .{ .input = "HeLLo", .expected = "hello" },
        .{ .input = "hello", .expected = "hello" },
        .{ .input = "Test123", .expected = "test123" },
        .{ .input = "ABC-DEF", .expected = "abc-def" },
        .{ .input = "½", .expected = "1⁄2" },
        .{ .input = "ℌello", .expected = "hello" },
        .{ .input = "ℓℯℓℓo", .expected = "lello" },
    };
    
    // Load character mappings
    var mappings = try static_data_loader.loadBasicMappings(allocator);
    defer mappings.deinit();
    
    for (test_cases) |test_case| {
        try stdout.print("Input: \"{s}\"\n", .{test_case.input});
        
        // Tokenize with mappings
        const tokenized = try tokenizer.TokenizedName.fromInputWithMappings(
            allocator,
            test_case.input,
            &mappings,
            false,
        );
        defer tokenized.deinit();
        
        // Build normalized output
        var result = std.ArrayList(u8).init(allocator);
        defer result.deinit();
        
        for (tokenized.tokens) |token| {
            const cps = token.getCps();
            for (cps) |cp| {
                const utf8_len = std.unicode.utf8CodepointSequenceLength(@as(u21, @intCast(cp))) catch continue;
                const old_len = result.items.len;
                try result.resize(old_len + utf8_len);
                _ = std.unicode.utf8Encode(@as(u21, @intCast(cp)), result.items[old_len..]) catch continue;
            }
        }
        
        try stdout.print("Output: \"{s}\"\n", .{result.items});
        try stdout.print("Expected: \"{s}\"\n", .{test_case.expected});
        
        if (std.mem.eql(u8, result.items, test_case.expected)) {
            try stdout.print("✓ PASS\n", .{});
        } else {
            try stdout.print("✗ FAIL\n", .{});
        }
        try stdout.print("\n", .{});
    }
}

test "character mappings integration" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test ASCII case folding
    const result = try root.normalize(allocator, "HELLO");
    defer allocator.free(result);
    try testing.expectEqualStrings("hello", result);
    
    // Test Unicode mappings
    const result2 = try root.normalize(allocator, "½");
    defer allocator.free(result2);
    try testing.expectEqualStrings("1⁄2", result2);
}