const std = @import("std");
const ens = @import("src/root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("Testing confusable detection...\n\n", .{});

    var ensip15 = try ens.Ensip15.init(allocator);
    defer ensip15.deinit();

    // Test 1: ASCII (should pass)
    std.debug.print("Test 1: Pure ASCII 'hello'\n", .{});
    if (ensip15.normalize(allocator, "hello")) |normalized| {
        defer allocator.free(normalized);
        std.debug.print("  ✓ Passed: '{s}'\n\n", .{normalized});
    } else |err| {
        std.debug.print("  ✗ Failed: {any}\n\n", .{err});
    }

    // Test 2: Cyrillic confusable (should fail with WholeConfusable)
    // "scope" but with Cyrillic 'с' (U+0441) and 'о' (U+043E)
    std.debug.print("Test 2: Cyrillic confusable 'sсоре'\n", .{});
    std.debug.print("  (contains Cyrillic с and о that look like Latin)\n", .{});
    if (ensip15.normalize(allocator, "sсоре")) |normalized| {
        defer allocator.free(normalized);
        std.debug.print("  ✗ Unexpected success: '{s}'\n\n", .{normalized});
    } else |err| {
        std.debug.print("  ✓ Expected error: {any}\n\n", .{err});
    }

    // Test 3: Greek (should pass)
    std.debug.print("Test 3: Greek 'αβγ'\n", .{});
    if (ensip15.normalize(allocator, "αβγ")) |normalized| {
        defer allocator.free(normalized);
        std.debug.print("  ✓ Passed: '{s}'\n\n", .{normalized});
    } else |err| {
        std.debug.print("  Result: {any}\n\n", .{err});
    }

    // Test 4: Mixed Latin-Cyrillic (should fail on mixing rules)
    std.debug.print("Test 4: Mixed Latin-Cyrillic 'aб'\n", .{});
    if (ensip15.normalize(allocator, "aб")) |normalized| {
        defer allocator.free(normalized);
        std.debug.print("  Result: '{s}'\n\n", .{normalized});
    } else |err| {
        std.debug.print("  Expected error (mixing): {any}\n\n", .{err});
    }

    std.debug.print("Done!\n", .{});
}
