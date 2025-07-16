const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Testing beautify with correct expectations:\n\n", .{});
    
    // Test 1: Single ξ forms a Greek label, so NO replacement
    {
        const input = "ξ.eth";
        const expected = "ξ.eth"; // Should NOT be replaced!
        
        const result = try ens_normalize.beautify_fn(allocator, input);
        defer allocator.free(result);
        
        const passed = std.mem.eql(u8, result, expected);
        std.debug.print("Test 1: '{s}' -> '{s}' [{s}]\n", .{input, result, if (passed) "PASS" else "FAIL"});
        std.debug.print("  (Single ξ forms Greek label, no replacement)\n", .{});
    }
    
    // Test 2: ξ in ASCII context should be replaced
    {
        const input = "ξtest.eth";
        const expected = "Ξtest.eth";
        
        const result = try ens_normalize.beautify_fn(allocator, input);
        defer allocator.free(result);
        
        const passed = std.mem.eql(u8, result, expected);
        std.debug.print("\nTest 2: '{s}' -> '{s}' [{s}]\n", .{input, result, if (passed) "PASS" else "FAIL"});
        std.debug.print("  (ξ in ASCII context, should be replaced)\n", .{});
    }
    
    // Test 3: ξ in Greek context should NOT be replaced
    {
        const input = "αξβ.eth";
        const expected = "αξβ.eth";
        
        const result = try ens_normalize.beautify_fn(allocator, input);
        defer allocator.free(result);
        
        const passed = std.mem.eql(u8, result, expected);
        std.debug.print("\nTest 3: '{s}' -> '{s}' [{s}]\n", .{input, result, if (passed) "PASS" else "FAIL"});
        std.debug.print("  (ξ in Greek context, no replacement)\n", .{});
    }
    
    // Test 4: From ENSIP-15 example
    {
        const input = "-ξ1⃣";
        const expected = "-Ξ1️⃣";
        
        const result = try ens_normalize.beautify_fn(allocator, input);
        defer allocator.free(result);
        
        std.debug.print("\nTest 4: '{s}' -> '{s}'\n", .{input, result});
        std.debug.print("  Expected: '{s}'\n", .{expected});
        std.debug.print("  (ENSIP-15 example)\n", .{});
    }
    
    // Test 5: Multiple labels with different contexts
    {
        const input = "ξtest.ξ.αξβ.eth";
        const expected = "Ξtest.ξ.αξβ.eth";
        
        const result = try ens_normalize.beautify_fn(allocator, input);
        defer allocator.free(result);
        
        const passed = std.mem.eql(u8, result, expected);
        std.debug.print("\nTest 5: '{s}' -> '{s}' [{s}]\n", .{input, result, if (passed) "PASS" else "FAIL"});
        std.debug.print("  (Mixed: ASCII w/ξ, Greek single ξ, Greek w/ξ)\n", .{});
    }
    
    std.debug.print("\nAll tests completed!\n", .{});
}