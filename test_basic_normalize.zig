const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    std.debug.print("Starting test...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Allocator initialized\n", .{});
    
    // Basic test cases that should work
    const test_cases = [_]struct {
        input: []const u8,
        expected: ?[]const u8,
        should_error: bool,
    }{
        .{ .input = "eth", .expected = "eth", .should_error = false },
        .{ .input = "ETH", .expected = "eth", .should_error = false },
        .{ .input = "hello", .expected = "hello", .should_error = false },
        .{ .input = "HELLO", .expected = "hello", .should_error = false },
        .{ .input = "test123", .expected = "test123", .should_error = false },
        .{ .input = "café", .expected = "café", .should_error = false },
        .{ .input = "", .expected = null, .should_error = true },
        .{ .input = ".", .expected = null, .should_error = true },
        .{ .input = " ", .expected = null, .should_error = true },
        .{ .input = "a b", .expected = null, .should_error = true },
    };
    
    std.debug.print("=== Basic Normalization Tests ===\n", .{});
    
    var passed: usize = 0;
    var failed: usize = 0;
    
    std.debug.print("About to start testing {} cases\n", .{test_cases.len});
    
    for (test_cases) |tc| {
        std.debug.print("\nTesting input: '{s}'", .{tc.input});
        if (tc.input.len > 0) {
            std.debug.print(" (hex:", .{});
            for (tc.input) |byte| {
                std.debug.print(" {x:0>2}", .{byte});
            }
            std.debug.print(")", .{});
        }
        std.debug.print("\n", .{});
        
        std.debug.print("Calling normalize...\n", .{});
        const result = ens.normalize(allocator, tc.input) catch |err| {
            if (tc.should_error) {
                std.debug.print("✅ Expected error: {}\n", .{err});
                passed += 1;
            } else {
                std.debug.print("❌ Unexpected error: {}\n", .{err});
                failed += 1;
            }
            continue;
        };
        defer allocator.free(result);
        
        if (tc.should_error) {
            std.debug.print("❌ Expected error but got: '{s}'\n", .{result});
            failed += 1;
        } else if (tc.expected) |expected| {
            if (std.mem.eql(u8, result, expected)) {
                std.debug.print("✅ Success: '{s}' -> '{s}'\n", .{tc.input, result});
                passed += 1;
            } else {
                std.debug.print("❌ Expected '{s}' but got '{s}'\n", .{expected, result});
                failed += 1;
            }
        }
    }
    
    std.debug.print("\n=== Summary ===\n", .{});
    std.debug.print("Passed: {}/{}\n", .{passed, passed + failed});
    std.debug.print("Failed: {}\n", .{failed});
}