const std = @import("std");
const root = @import("root.zig");
const static_data_loader = @import("static_data_loader.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("Testing spec.json loading\n", .{});
    try stdout.print("========================\n\n", .{});
    
    // Load from spec.json
    const start_time = std.time.milliTimestamp();
    var mappings = try static_data_loader.loadCharacterMappings(allocator);
    defer mappings.deinit();
    const load_time = std.time.milliTimestamp() - start_time;
    
    try stdout.print("✓ Successfully loaded spec.json in {}ms\n\n", .{load_time});
    
    // Count loaded data
    var mapped_count: usize = 0;
    var ignored_count: usize = 0; 
    var valid_count: usize = 0;
    
    var mapped_iter = mappings.unicode_mappings.iterator();
    while (mapped_iter.next()) |_| {
        mapped_count += 1;
    }
    
    var ignored_iter = mappings.ignored_chars.iterator();
    while (ignored_iter.next()) |_| {
        ignored_count += 1;
    }
    
    var valid_iter = mappings.valid_chars.iterator();
    while (valid_iter.next()) |_| {
        valid_count += 1;
    }
    
    try stdout.print("Loaded data statistics:\n", .{});
    try stdout.print("- Mapped characters: {}\n", .{mapped_count});
    try stdout.print("- Ignored characters: {}\n", .{ignored_count});
    try stdout.print("- Valid characters: {}\n", .{valid_count});
    try stdout.print("\n", .{});
    
    // Test some specific mappings
    try stdout.print("Sample mappings:\n", .{});
    
    const test_cases = [_]struct { cp: u32, name: []const u8 }{
        .{ .cp = 39, .name = "apostrophe" },      // ' -> '
        .{ .cp = 65, .name = "A" },              // A -> a
        .{ .cp = 8217, .name = "right quote" },  // ' (should have no mapping)
        .{ .cp = 8450, .name = "ℂ" },            // ℂ -> c
        .{ .cp = 8460, .name = "ℌ" },            // ℌ -> h
        .{ .cp = 189, .name = "½" },             // ½ -> 1⁄2
    };
    
    for (test_cases) |test_case| {
        if (mappings.getMapped(test_case.cp)) |mapped| {
            try stdout.print("- {s} (U+{X:0>4}): maps to", .{ test_case.name, test_case.cp });
            for (mapped) |cp| {
                try stdout.print(" U+{X:0>4}", .{cp});
            }
            try stdout.print("\n", .{});
        } else {
            try stdout.print("- {s} (U+{X:0>4}): no mapping\n", .{ test_case.name, test_case.cp });
        }
    }
    
    try stdout.print("\n", .{});
    
    // Test ignored characters
    try stdout.print("Sample ignored characters:\n", .{});
    const ignored_tests = [_]u32{ 173, 8204, 8205, 65279 };
    for (ignored_tests) |cp| {
        const is_ignored = mappings.isIgnored(cp);
        try stdout.print("- U+{X:0>4}: {}\n", .{ cp, is_ignored });
    }
    
    try stdout.print("\n", .{});
    
    // Test valid characters
    try stdout.print("Sample valid characters:\n", .{});
    const valid_tests = [_]u32{ 'a', 'z', '0', '9', '-', '_', '.', 8217 };
    for (valid_tests) |cp| {
        const is_valid = mappings.isValid(cp);
        try stdout.print("- '{}' (U+{X:0>4}): {}\n", .{ 
            if (cp < 128) @as(u8, @intCast(cp)) else '?', 
            cp, 
            is_valid 
        });
    }
}