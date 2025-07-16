const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test Greek character replacement with detailed tracing
    {
        const input = "ξ.eth";
        std.debug.print("\n=== Testing: '{s}' ===\n", .{input});
        
        // First, let's process it to see what label types we get
        const processed = try ens_normalize.process(allocator, input);
        defer processed.deinit();
        
        std.debug.print("Number of labels: {}\n", .{processed.labels.len});
        for (processed.labels, 0..) |label, i| {
            std.debug.print("Label[{}]: type={s}\n", .{i, @tagName(label.label_type)});
        }
        
        // Now beautify
        const result = try processed.beautify();
        defer allocator.free(result);
        
        std.debug.print("Beautified result: '{s}'\n", .{result});
        std.debug.print("Expected: 'Ξ.eth'\n", .{});
        
        // Check the actual bytes
        std.debug.print("Result bytes: ", .{});
        for (result) |byte| {
            std.debug.print("{X:0>2} ", .{byte});
        }
        std.debug.print("\n", .{});
        
        // Expected bytes for Ξ (U+039E)
        std.debug.print("Expected bytes: CE 9E 2E 65 74 68\n", .{});
    }
}