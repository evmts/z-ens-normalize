const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Just check if these characters are in the ignored list
    var specs = ens.code_points.CodePointsSpecs.init(allocator);
    defer specs.deinit();
    
    var char_mappings = try ens.static_data_loader.loadCharacterMappings(allocator);
    defer char_mappings.deinit();
    
    const zwnj: u32 = 0x200C;
    const zwj: u32 = 0x200D;
    
    std.debug.print("=== ZWJ/ZWNJ Character Status ===\n\n", .{});
    
    // Check ZWNJ (should not be ignored, valid, or mapped)
    std.debug.print("ZWNJ (U+200C):\n", .{});
    std.debug.print("  Is ignored: {}\n", .{char_mappings.isIgnored(zwnj)});
    std.debug.print("  Is valid: {}\n", .{char_mappings.isValid(zwnj)});
    std.debug.print("  Is mapped: {}\n", .{char_mappings.getMapped(zwnj) != null});
    std.debug.print("  Expected: Not ignored, not valid, not mapped (= disallowed)\n", .{});
    
    std.debug.print("\nZWJ (U+200D):\n", .{});
    std.debug.print("  Is ignored: {}\n", .{char_mappings.isIgnored(zwj)});
    std.debug.print("  Is valid: {}\n", .{char_mappings.isValid(zwj)});
    std.debug.print("  Is mapped: {}\n", .{char_mappings.getMapped(zwj) != null});
    std.debug.print("  Expected: Not ignored, not valid, not mapped (= disallowed except in emoji)\n", .{});
    
    // Check some known ignored characters for comparison
    const soft_hyphen: u32 = 0x00AD; // Should be ignored
    std.debug.print("\nSoft Hyphen (U+00AD) for comparison:\n", .{});
    std.debug.print("  Is ignored: {}\n", .{char_mappings.isIgnored(soft_hyphen)});
    
    std.debug.print("\nTest complete\n", .{});
}