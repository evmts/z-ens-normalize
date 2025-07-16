const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Log level is set via environment variable ENS_LOG_LEVEL
    std.debug.print("\n=== ENS Normalize Debug Logging Test ===\n\n", .{});
    std.debug.print("Set ENS_LOG_LEVEL=debug or ENS_LOG_LEVEL=trace for more output\n\n", .{});
    
    // Test cases
    const test_cases = [_][]const u8{
        "vitalik.eth",
        "VITALIK.ETH",  // Test uppercase mapping
        "🦄🌈.eth",      // Test emoji
        "abc‍def.eth",   // Test with zero-width joiner
        "ℌello.eth",     // Test special character mapping
        "",              // Test empty
    };
    
    for (test_cases) |input| {
        std.debug.print("\n--- Testing: \"{s}\" ---\n", .{input});
        
        const result = ens_normalize.normalize(allocator, input) catch |err| {
            std.debug.print("Normalization failed: {}\n", .{err});
            continue;
        };
        defer allocator.free(result);
        
        std.debug.print("Result: \"{s}\"\n", .{result});
    }
    
    std.debug.print("\n=== Test Complete ===\n", .{});
}