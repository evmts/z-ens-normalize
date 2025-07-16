const std = @import("std");
const ens_normalize = @import("ens_normalize");

// Test to understand how script detection should work
pub fn main() !void {
    _ = ens_normalize; // Mark as used
    
    // Greek alphabet codepoint ranges:
    // Greek and Coptic: U+0370 - U+03FF
    // Greek Extended: U+1F00 - U+1FFF
    
    const test_cases = [_]struct {
        input: []const u8,
        description: []const u8,
        expected_script: []const u8,
    }{
        // Pure Greek words
        .{ .input = "ξένος", .description = "Greek word 'xenos'", .expected_script = "Greek" },
        .{ .input = "αλέξανδρος", .description = "Greek name 'alexandros'", .expected_script = "Greek" },
        .{ .input = "ξυλόφωνο", .description = "Greek word 'xylophone'", .expected_script = "Greek" },
        .{ .input = "Ξένος", .description = "Greek word with capital Xi", .expected_script = "Greek" },
        
        // Mixed scripts (should not be Greek)
        .{ .input = "ξcoin", .description = "Greek xi with Latin", .expected_script = "Mixed/Latin" },
        .{ .input = "Ξeth", .description = "Greek Xi with Latin", .expected_script = "Mixed/Latin" },
        .{ .input = "hello", .description = "Pure Latin", .expected_script = "Latin" },
        .{ .input = "123", .description = "Numbers only", .expected_script = "ASCII" },
    };
    
    std.debug.print("\n=== Script Detection Test ===\n\n", .{});
    
    for (test_cases) |tc| {
        std.debug.print("Input: \"{s}\"\n", .{tc.input});
        std.debug.print("Description: {s}\n", .{tc.description});
        std.debug.print("Expected script: {s}\n", .{tc.expected_script});
        
        // Check each character
        const view = try std.unicode.Utf8View.init(tc.input);
        var iter = view.iterator();
        
        var has_greek = false;
        var has_latin = false;
        var has_other = false;
        var all_ascii = true;
        
        while (iter.nextCodepoint()) |cp| {
            std.debug.print("  U+{X:0>4}: ", .{cp});
            
            if (cp < 0x80) {
                // ASCII
                if ((cp >= 'a' and cp <= 'z') or (cp >= 'A' and cp <= 'Z')) {
                    has_latin = true;
                    std.debug.print("ASCII Latin\n", .{});
                } else {
                    std.debug.print("ASCII other\n", .{});
                }
            } else {
                all_ascii = false;
                
                // Check if it's Greek
                if ((cp >= 0x0370 and cp <= 0x03FF) or // Greek and Coptic
                    (cp >= 0x1F00 and cp <= 0x1FFF))   // Greek Extended
                {
                    has_greek = true;
                    std.debug.print("Greek\n", .{});
                } else {
                    has_other = true;
                    std.debug.print("Other Unicode\n", .{});
                }
            }
        }
        
        std.debug.print("Analysis: ", .{});
        if (has_greek and !has_latin and !has_other) {
            std.debug.print("Pure Greek script\n", .{});
        } else if (has_greek and (has_latin or has_other)) {
            std.debug.print("Mixed script (contains Greek)\n", .{});
        } else if (all_ascii) {
            std.debug.print("Pure ASCII\n", .{});
        } else {
            std.debug.print("Other script\n", .{});
        }
        
        std.debug.print("\n", .{});
    }
}