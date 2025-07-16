const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    std.debug.print("Test starting\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("Creating specs...\n", .{});
    var specs = ens.code_points.CodePointsSpecs.init(allocator);
    defer specs.deinit();
    
    std.debug.print("Specs created\n", .{});
    
    // Test simple ASCII check
    std.debug.print("CodePointsSpecs initialized successfully\n", .{});
    
    std.debug.print("Test complete\n", .{});
}