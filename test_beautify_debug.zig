const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // First test without emoji to make sure basic functionality works
    {
        const input = "test.eth";
        std.debug.print("Testing simple input: '{s}'\n", .{input});
        const result = try ens_normalize.beautify_fn(allocator, input);
        defer allocator.free(result);
        std.debug.print("Result: '{s}'\n", .{result});
    }
    
    // Test Greek character replacement
    {
        const input = "ξ.eth";
        std.debug.print("\nTesting Greek character: '{s}'\n", .{input});
        const result = try ens_normalize.beautify_fn(allocator, input);
        defer allocator.free(result);
        std.debug.print("Result: '{s}' (expected: 'Ξ.eth')\n", .{result});
    }
    
    // Now test with simple emoji
    {
        const input = "test💩.eth";
        std.debug.print("\nTesting with poop emoji: '{s}'\n", .{input});
        const result = ens_normalize.beautify_fn(allocator, input) catch |err| {
            std.debug.print("Error: {}\n", .{err});
            return;
        };
        defer allocator.free(result);
        std.debug.print("Result: '{s}'\n", .{result});
    }
    
    std.debug.print("\nDone!\n", .{});
}