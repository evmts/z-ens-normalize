const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    std.debug.print("\n=== Greek Xi (ξ/Ξ) Beautify Test Cases ===\n\n", .{});
    
    // Test cases showing the beautify behavior for Greek xi
    const test_cases = [_]struct {
        input: []const u8,
        expected_beautified: []const u8,
        description: []const u8,
    }{
        // Non-Greek context: ξ => Ξ in beautify
        .{ .input = "ξcoin", .expected_beautified = "Ξcoin", .description = "Lowercase xi at start" },
        .{ .input = "Ξcoin", .expected_beautified = "Ξcoin", .description = "Uppercase Xi stays uppercase" },
        .{ .input = "ΞETH", .expected_beautified = "ΞETH", .description = "Uppercase Xi with uppercase text" },
        .{ .input = "ξeth", .expected_beautified = "Ξeth", .description = "Lowercase xi with lowercase text" },
        .{ .input = "mΞrge", .expected_beautified = "mΞrge", .description = "Uppercase Xi in middle" },
        .{ .input = "mξrge", .expected_beautified = "mΞrge", .description = "Lowercase xi in middle" },
        .{ .input = "porschΞ911", .expected_beautified = "porschΞ911", .description = "Uppercase Xi with numbers" },
        .{ .input = "porschξ911", .expected_beautified = "porschΞ911", .description = "Lowercase xi with numbers" },
        .{ .input = "ξ-ξ-ξ", .expected_beautified = "Ξ-Ξ-Ξ", .description = "Multiple lowercase xi" },
        .{ .input = "Ξ-Ξ-Ξ", .expected_beautified = "Ξ-Ξ-Ξ", .description = "Multiple uppercase Xi" },
        .{ .input = "ξ333", .expected_beautified = "Ξ333", .description = "Xi with numbers only" },
        .{ .input = "ξvisawallet", .expected_beautified = "Ξvisawallet", .description = "Xi in compound word" },
    };
    
    for (test_cases) |tc| {
        std.debug.print("Input: \"{s}\"\n", .{tc.input});
        std.debug.print("Expected beautified: \"{s}\"\n", .{tc.expected_beautified});
        std.debug.print("Description: {s}\n", .{tc.description});
        
        // Test normalize (should always lowercase Xi)
        const normalized = try ens_normalize.normalize(allocator, tc.input);
        defer allocator.free(normalized);
        
        std.debug.print("Normalized: \"{s}\"\n", .{normalized});
        
        // Test beautify
        const beautified = try ens_normalize.beautify_fn(allocator, tc.input);
        defer allocator.free(beautified);
        
        std.debug.print("Beautified: \"{s}\" ", .{beautified});
        if (std.mem.eql(u8, beautified, tc.expected_beautified)) {
            std.debug.print("✓\n", .{});
        } else {
            std.debug.print("✗ MISMATCH!\n", .{});
        }
        
        std.debug.print("\n", .{});
    }
    
    std.debug.print("=== Greek Script Context Test ===\n\n", .{});
    std.debug.print("Note: In pure Greek script context, ξ should remain lowercase in beautify\n\n", .{});
    
    // Greek context test cases
    const greek_tests = [_]struct {
        input: []const u8,
        expected_beautified: []const u8,
        description: []const u8,
    }{
        .{ .input = "ξένος", .expected_beautified = "ξένος", .description = "Greek word 'xenos'" },
        .{ .input = "αλέξανδρος", .expected_beautified = "αλέξανδρος", .description = "Greek name 'alexandros'" },
        .{ .input = "ξυλόφωνο", .expected_beautified = "ξυλόφωνο", .description = "Greek word 'xylophone'" },
        .{ .input = "Ξένος", .expected_beautified = "Ξένος", .description = "Greek word with capital Xi" },
    };
    
    for (greek_tests) |tc| {
        std.debug.print("Input: \"{s}\"\n", .{tc.input});
        std.debug.print("Expected beautified: \"{s}\"\n", .{tc.expected_beautified});
        std.debug.print("Description: {s}\n", .{tc.description});
        
        const normalized = try ens_normalize.normalize(allocator, tc.input);
        defer allocator.free(normalized);
        
        const beautified = try ens_normalize.beautify_fn(allocator, tc.input);
        defer allocator.free(beautified);
        
        std.debug.print("Normalized: \"{s}\"\n", .{normalized});
        std.debug.print("Beautified: \"{s}\" ", .{beautified});
        if (std.mem.eql(u8, beautified, tc.expected_beautified)) {
            std.debug.print("✓\n", .{});
        } else {
            std.debug.print("✗ MISMATCH!\n", .{});
        }
        
        std.debug.print("\n", .{});
    }
}