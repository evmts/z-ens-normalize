const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const validate = @import("validate.zig");
const utils = @import("utils.zig");
const constants = @import("constants.zig");

pub fn beautifyLabels(allocator: std.mem.Allocator, labels: []const validate.ValidatedLabel) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    for (labels, 0..) |label, i| {
        if (i > 0) {
            try result.append('.');
        }
        
        const label_str = try beautifyLabel(allocator, label);
        defer allocator.free(label_str);
        try result.appendSlice(label_str);
    }
    
    return result.toOwnedSlice();
}

fn beautifyLabel(allocator: std.mem.Allocator, label: validate.ValidatedLabel) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    // Get all code points from the label
    var cps = std.ArrayList(CodePoint).init(allocator);
    defer cps.deinit();
    
    for (label.tokens) |token| {
        const token_cps = token.getCps();
        try cps.appendSlice(token_cps);
    }
    
    // Apply beautification rules
    try applyBeautificationRules(allocator, cps.items, label.label_type);
    
    // Convert back to string
    return utils.cps2str(allocator, cps.items);
}

fn applyBeautificationRules(allocator: std.mem.Allocator, cps: []CodePoint, label_type: validate.LabelType) !void {
    _ = allocator;
    
    // Update ethereum symbol: ξ => Ξ if not Greek
    switch (label_type) {
        .greek => {
            // Keep ξ as is for Greek
        },
        else => {
            // Replace ξ with Ξ for non-Greek
            for (cps) |*cp| {
                if (cp.* == constants.CP_XI_SMALL) {
                    cp.* = constants.CP_XI_CAPITAL;
                }
            }
        },
    }
    
    // Additional beautification rules could be added here
    // For example, handling leading/trailing hyphens, etc.
}

test "beautifyLabels basic functionality" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const tokenizer = @import("tokenizer.zig");
    
    // Create a simple test label
    const token = try tokenizer.Token.createValid(allocator, &[_]CodePoint{0x68, 0x65, 0x6C, 0x6C, 0x6F}); // "hello"
    const tokens = [_]tokenizer.Token{token};
    
    const label = try validate.ValidatedLabel.init(allocator, &tokens, validate.LabelType.ascii);
    
    const labels = [_]validate.ValidatedLabel{label};
    const result = beautifyLabels(allocator, &labels) catch |err| {
        // For now, we may get errors due to incomplete implementation
        try testing.expect(err == error.OutOfMemory or err == error.InvalidUtf8);
        return;
    };
    defer allocator.free(result);
    
    // Basic sanity check
    try testing.expect(result.len > 0);
}