const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test empty string
    std.debug.print("Testing empty string...\n", .{});
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.debug.print("Failed to initialize normalizer: {}\n", .{err});
        return;
    };
    defer normalizer.deinit();
    
    const result = normalizer.normalize("");
    if (result) |normalized| {
        defer allocator.free(normalized);
        std.debug.print("ERROR: Empty string should fail but got: '{s}'\n", .{normalized});
    } else |err| {
        std.debug.print("SUCCESS: Empty string correctly failed with: {}\n", .{err});
    }
}