const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test what script group ξ belongs to
    const xi_cp: u32 = 0x3BE; // ξ
    
    std.debug.print("Testing codepoint ξ (U+{X:0>4})\n", .{xi_cp});
    
    // Load script groups data
    const script_groups_data = try ens_normalize.static_data_loader.loadScriptGroups(allocator);
    defer script_groups_data.deinit();
    
    // Find groups containing this codepoint
    const containing_groups = try script_groups_data.findGroupsContaining(xi_cp, allocator);
    defer allocator.free(containing_groups);
    
    std.debug.print("Found {} groups containing ξ:\n", .{containing_groups.len});
    for (containing_groups, 0..) |group, i| {
        std.debug.print("  [{}] {s}\n", .{i, group.name});
    }
    
    // Test with a simple label
    const tokenizer = @import("tokenizer.zig");
    const token = try tokenizer.Token.createValid(allocator, &[_]u32{xi_cp});
    defer token.deinit();
    
    const tokens = [_]tokenizer.Token{token};
    const label = ens_normalize.validate.TokenizedLabel{
        .tokens = &tokens,
        .allocator = allocator,
    };
    
    // Try to determine script group
    const group = script_groups_data.determineScriptGroup(&[_]u32{xi_cp}, allocator) catch |err| {
        std.debug.print("Error determining script group: {}\n", .{err});
        return;
    };
    
    std.debug.print("Determined script group: {s}\n", .{group.name});
}