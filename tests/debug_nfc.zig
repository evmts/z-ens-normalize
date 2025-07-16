const std = @import("std");
const testing = std.testing;

test "debug NFC codepoints" {
    const combining = "cafe\u{0301}"; // café with combining acute accent  
    const precomposed = "café"; // café with precomposed é
    
    std.debug.print("\nCombining: '{s}'\n", .{combining});
    std.debug.print("Precomposed: '{s}'\n", .{precomposed});
    
    // Print codepoints
    std.debug.print("Combining codepoints: ", .{});
    var iter1 = std.unicode.Utf8Iterator{.bytes = combining, .i = 0};
    while (iter1.nextCodepoint()) |cp| {
        std.debug.print("U+{X:0>4} ", .{cp});
    }
    std.debug.print("\n", .{});
    
    std.debug.print("Precomposed codepoints: ", .{});
    var iter2 = std.unicode.Utf8Iterator{.bytes = precomposed, .i = 0};
    while (iter2.nextCodepoint()) |cp| {
        std.debug.print("U+{X:0>4} ", .{cp});
    }
    std.debug.print("\n", .{});
    
    std.debug.print("Are they equal? {}\n", .{std.mem.eql(u8, combining, precomposed)});
}