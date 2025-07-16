const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test Greek character replacement
    {
        const input = "ξtest.eth";
        const result = try ens_normalize.beautify_fn(allocator, input);
        defer allocator.free(result);
        
        std.debug.print("Test 1: '{s}' -> '{s}' (expected: 'Ξtest.eth')\n", .{input, result});
        if (!std.mem.eql(u8, result, "Ξtest.eth")) {
            std.debug.print("FAIL: Expected 'Ξtest.eth', got '{s}'\n", .{result});
            return error.TestFailed;
        }
    }
    
    // Test Greek label (should NOT replace)
    {
        const input = "αξβ.eth";
        const result = try ens_normalize.beautify_fn(allocator, input);
        defer allocator.free(result);
        
        std.debug.print("Test 2: '{s}' -> '{s}' (expected: 'αξβ.eth')\n", .{input, result});
        if (!std.mem.eql(u8, result, "αξβ.eth")) {
            std.debug.print("FAIL: Expected 'αξβ.eth', got '{s}'\n", .{result});
            return error.TestFailed;
        }
    }
    
    // Test emoji preservation
    {
        const input = "1⃣.eth";
        const result = try ens_normalize.beautify_fn(allocator, input);
        defer allocator.free(result);
        
        std.debug.print("Test 3: '{s}' -> '{s}' (expected: '1️⃣.eth')\n", .{input, result});
        // Note: We expect the fully-qualified emoji with FE0F
    }
    
    // Test from ENSIP-15 documentation
    {
        const input = "-ξ1⃣";
        const result = try ens_normalize.beautify_fn(allocator, input);
        defer allocator.free(result);
        
        std.debug.print("Test 4: '{s}' -> '{s}' (expected: '-Ξ1️⃣')\n", .{input, result});
    }
    
    std.debug.print("All beautify tests completed!\n", .{});
}