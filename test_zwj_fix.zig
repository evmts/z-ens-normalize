const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    std.debug.print("=== Testing ZWNJ/ZWJ Character Classification ===\n\n", .{});
    
    // Load character mappings
    var char_mappings = try ens.static_data_loader.loadCharacterMappings(allocator);
    defer char_mappings.deinit();
    
    // Test characters
    const test_chars = [_]struct {
        cp: u32,
        name: []const u8,
        expected_ignored: bool,
        expected_valid: bool,
        expected_mapped: bool,
    }{
        .{ .cp = 0x200C, .name = "ZWNJ", .expected_ignored = false, .expected_valid = false, .expected_mapped = false },
        .{ .cp = 0x200D, .name = "ZWJ", .expected_ignored = false, .expected_valid = false, .expected_mapped = false },
        .{ .cp = 0x00AD, .name = "Soft Hyphen", .expected_ignored = true, .expected_valid = false, .expected_mapped = false },
        .{ .cp = 'a', .name = "a", .expected_ignored = false, .expected_valid = true, .expected_mapped = false },
        .{ .cp = 'A', .name = "A", .expected_ignored = false, .expected_valid = false, .expected_mapped = true },
    };
    
    var passed: usize = 0;
    var failed: usize = 0;
    
    for (test_chars) |tc| {
        const is_ignored = char_mappings.isIgnored(tc.cp);
        const is_valid = char_mappings.isValid(tc.cp);
        const is_mapped = char_mappings.getMapped(tc.cp) != null;
        
        std.debug.print("U+{X:0>4} ({s}):\n", .{tc.cp, tc.name});
        std.debug.print("  Ignored: {} (expected: {})\n", .{is_ignored, tc.expected_ignored});
        std.debug.print("  Valid: {} (expected: {})\n", .{is_valid, tc.expected_valid});
        std.debug.print("  Mapped: {} (expected: {})\n", .{is_mapped, tc.expected_mapped});
        
        const all_correct = (is_ignored == tc.expected_ignored) and 
                           (is_valid == tc.expected_valid) and 
                           (is_mapped == tc.expected_mapped);
        
        if (all_correct) {
            std.debug.print("  ✅ PASS\n", .{});
            passed += 1;
        } else {
            std.debug.print("  ❌ FAIL\n", .{});
            failed += 1;
        }
        
        // If not ignored, valid, or mapped, it's disallowed
        if (!is_ignored and !is_valid and !is_mapped) {
            std.debug.print("  => Character is DISALLOWED\n", .{});
        }
        std.debug.print("\n", .{});
    }
    
    std.debug.print("=== Summary ===\n", .{});
    std.debug.print("Passed: {}/{}\n", .{passed, test_chars.len});
    std.debug.print("Failed: {}\n", .{failed});
    
    if (passed == test_chars.len) {
        std.debug.print("\n✅ All character classifications are correct!\n", .{});
    }
}