const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");

test "NFC normalization - failing test demonstrating the issue" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Input: "café" with combining acute accent (5 codepoints: c-a-f-e-◌́)
    const input_combining = "cafe\u{0301}";
    
    // Expected: "café" with precomposed é (4 codepoints: c-a-f-é)  
    const expected_precomposed = "café";
    
    std.debug.print("\n=== NFC NORMALIZATION FAILING TEST ===\n", .{});
    std.debug.print("Input (combining): '{s}' (len={})\n", .{input_combining, input_combining.len});
    std.debug.print("Expected (precomposed): '{s}' (len={})\n", .{expected_precomposed, expected_precomposed.len});
    
    // Our normalize function should convert combining to precomposed
    const result = try ens_normalize.normalize(allocator, input_combining);
    defer allocator.free(result);
    
    std.debug.print("Actual result: '{s}' (len={})\n", .{result, result.len});
    
    // Print codepoints to show the difference
    std.debug.print("\nCodepoint analysis:\n", .{});
    
    std.debug.print("Input codepoints: ", .{});
    var iter1 = std.unicode.Utf8Iterator{.bytes = input_combining, .i = 0};
    while (iter1.nextCodepoint()) |cp| {
        std.debug.print("U+{X:0>4} ", .{cp});
    }
    std.debug.print("\n", .{});
    
    std.debug.print("Result codepoints: ", .{});
    var iter2 = std.unicode.Utf8Iterator{.bytes = result, .i = 0};
    while (iter2.nextCodepoint()) |cp| {
        std.debug.print("U+{X:0>4} ", .{cp});
    }
    std.debug.print("\n", .{});
    
    std.debug.print("Expected codepoints: ", .{});
    var iter3 = std.unicode.Utf8Iterator{.bytes = expected_precomposed, .i = 0};
    while (iter3.nextCodepoint()) |cp| {
        std.debug.print("U+{X:0>4} ", .{cp});
    }
    std.debug.print("\n", .{});
    
    std.debug.print("\nAnalysis:\n", .{});
    if (std.mem.eql(u8, result, input_combining)) {
        std.debug.print("❌ Result matches input - NFC normalization NOT applied\n", .{});
    } else if (std.mem.eql(u8, result, expected_precomposed)) {
        std.debug.print("✅ Result matches expected - NFC normalization correctly applied\n", .{});
    } else {
        std.debug.print("⚠️  Result differs from both input and expected\n", .{});
    }
    
    // This assertion will fail, proving NFC normalization is not working
    try testing.expectEqualStrings(expected_precomposed, result);
}