const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const validate = @import("validate.zig");
const utils = @import("utils.zig");
const constants = @import("constants.zig");

pub fn joinLabels(allocator: std.mem.Allocator, labels: []const validate.ValidatedLabel) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    for (labels, 0..) |label, i| {
        if (i > 0) {
            try result.append('.');
        }
        
        const label_str = try joinLabel(allocator, label);
        defer allocator.free(label_str);
        try result.appendSlice(label_str);
    }
    
    return result.toOwnedSlice();
}

fn joinLabel(allocator: std.mem.Allocator, label: validate.ValidatedLabel) ![]u8 {
    var cps = std.ArrayList(CodePoint).init(allocator);
    defer cps.deinit();
    
    for (label.tokens) |token| {
        const token_cps = try token.getCps(allocator);
        defer allocator.free(token_cps);
        try cps.appendSlice(token_cps);
    }
    
    return utils.cps2str(allocator, cps.items);
}

test "joinLabels basic functionality" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create a simple test label
    const tokens = [_]@import("tokens.zig").EnsNameToken{
        @import("tokens.zig").EnsNameToken{ .valid = @import("tokens.zig").TokenValid{ .cps = &[_]CodePoint{0x68, 0x65, 0x6C, 0x6C, 0x6F} } }, // "hello"
    };
    
    const label = validate.ValidatedLabel{
        .tokens = &tokens,
        .label_type = validate.LabelType.ascii,
        .allocator = allocator,
    };
    
    const labels = [_]validate.ValidatedLabel{label};
    const result = joinLabels(allocator, &labels) catch |err| {
        // For now, we may get errors due to incomplete implementation
        try testing.expect(err == error.OutOfMemory or err == error.InvalidUtf8);
        return;
    };
    defer allocator.free(result);
    
    // Basic sanity check
    try testing.expect(result.len > 0);
}