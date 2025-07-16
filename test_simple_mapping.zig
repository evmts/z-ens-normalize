const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    std.debug.print("Starting simple mapping test...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test direct character mapping
    std.debug.print("Loading character mappings...\n", .{});
    var char_mappings = try ens.static_data_loader.loadCharacterMappings(allocator);
    defer char_mappings.deinit();
    
    std.debug.print("Character mappings loaded successfully\n", .{});
    
    // Test some basic mappings
    const test_chars = [_]struct { cp: u32, name: []const u8 }{
        .{ .cp = 'A', .name = "A" },
        .{ .cp = 'Z', .name = "Z" },
        .{ .cp = 'a', .name = "a" },
        .{ .cp = 'z', .name = "z" },
        .{ .cp = '0', .name = "0" },
        .{ .cp = '9', .name = "9" },
    };
    
    for (test_chars) |tc| {
        const mapped = char_mappings.getMapped(tc.cp);
        if (mapped) |m| {
            std.debug.print("U+{X:0>4} ({s}) maps to: [", .{tc.cp, tc.name});
            for (m, 0..) |cp, i| {
                if (i > 0) std.debug.print(", ", .{});
                std.debug.print("U+{X:0>4}", .{cp});
            }
            std.debug.print("]\n", .{});
        } else {
            std.debug.print("U+{X:0>4} ({s}) has no mapping\n", .{tc.cp, tc.name});
        }
    }
    
    std.debug.print("Test complete\n", .{});
}