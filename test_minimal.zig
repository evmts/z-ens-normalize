const std = @import("std");

pub fn main() !void {
    std.debug.print("Test starting\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Just test basic string operations
    const input = "hello";
    const duped = try allocator.dupe(u8, input);
    defer allocator.free(duped);
    
    std.debug.print("Input: {s}\n", .{input});
    std.debug.print("Duped: {s}\n", .{duped});
    
    // Test UTF-8 encoding
    var buf: [4]u8 = undefined;
    const len = try std.unicode.utf8Encode('A', &buf);
    std.debug.print("Encoded 'A' in {} bytes\n", .{len});
    
    std.debug.print("Test complete\n", .{});
}