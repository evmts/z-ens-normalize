const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test cases from reference_tests.json
    const test_cases = [_]struct {
        name: []const u8,
        input: []const u8,
        should_error: bool,
        expected: ?[]const u8,
    }{
        .{ .name = "empty", .input = "", .should_error = true, .expected = null },
        .{ .name = "space", .input = " ", .should_error = true, .expected = null },
        .{ .name = "period", .input = ".", .should_error = true, .expected = null },
        .{ .name = "eth", .input = "eth", .should_error = false, .expected = "eth" },
        .{ .name = "ETH", .input = "ETH", .should_error = false, .expected = "eth" },
        .{ .name = "Eth", .input = "Eth", .should_error = false, .expected = "eth" },
        .{ .name = "underscore", .input = "_", .should_error = false, .expected = "_" },
        .{ .name = "hyphen", .input = "-", .should_error = false, .expected = "-" },
        .{ .name = "leading_hyphen", .input = "-a", .should_error = true, .expected = null },
        .{ .name = "trailing_hyphen", .input = "a-", .should_error = true, .expected = null },
        .{ .name = "double_hyphen", .input = "a--a", .should_error = false, .expected = "a--a" },
        .{ .name = "underscore_start", .input = "_a", .should_error = false, .expected = "_a" },
        .{ .name = "number", .input = "0", .should_error = false, .expected = "0" },
        .{ .name = "number_123", .input = "123", .should_error = false, .expected = "123" },
        .{ .name = "leading_zero", .input = "0123", .should_error = false, .expected = "0123" },
        .{ .name = "leading_zero_x", .input = "0x0", .should_error = false, .expected = "0x0" },
        .{ .name = "leading_zero_x_caps", .input = "0X0", .should_error = false, .expected = "0x0" },
        .{ .name = "zero_x", .input = "0x", .should_error = false, .expected = "0x" },
        .{ .name = "zero_x_cyrillic", .input = "0х", .should_error = true, .expected = null }, // Cyrillic х
        .{ .name = "dollarsign", .input = "$", .should_error = false, .expected = "$" },
        .{ .name = "emoji_heart", .input = "❤", .should_error = false, .expected = "❤" },
        .{ .name = "emoji_heart_fe0f", .input = "❤️", .should_error = false, .expected = "❤️" },
        .{ .name = "cafe", .input = "café", .should_error = false, .expected = "café" },
    };
    
    var passed: usize = 0;
    var failed: usize = 0;
    
    for (test_cases) |tc| {
        std.debug.print("\nTest: {s}\n", .{tc.name});
        std.debug.print("  Input: '{s}'", .{tc.input});
        
        // Show hex for non-ASCII
        var has_non_ascii = false;
        for (tc.input) |byte| {
            if (byte > 127) {
                has_non_ascii = true;
                break;
            }
        }
        if (has_non_ascii) {
            std.debug.print(" (hex:", .{});
            for (tc.input) |byte| {
                std.debug.print(" {x:0>2}", .{byte});
            }
            std.debug.print(")", .{});
        }
        std.debug.print("\n", .{});
        
        const result = ens.normalize(allocator, tc.input) catch |err| {
            if (tc.should_error) {
                std.debug.print("  ✅ Expected error: {}\n", .{err});
                passed += 1;
            } else {
                std.debug.print("  ❌ Unexpected error: {}\n", .{err});
                failed += 1;
            }
            continue;
        };
        defer allocator.free(result);
        
        if (tc.should_error) {
            std.debug.print("  ❌ Expected error but got: '{s}'\n", .{result});
            failed += 1;
        } else if (tc.expected) |expected| {
            if (std.mem.eql(u8, result, expected)) {
                std.debug.print("  ✅ Got expected: '{s}'\n", .{result});
                passed += 1;
            } else {
                std.debug.print("  ❌ Expected '{s}' but got '{s}'\n", .{expected, result});
                failed += 1;
            }
        }
    }
    
    std.debug.print("\n=== SUMMARY ===\n", .{});
    std.debug.print("Passed: {}/{}\n", .{passed, passed + failed});
    std.debug.print("Failed: {}\n", .{failed});
}