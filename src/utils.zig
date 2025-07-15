const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const constants = @import("constants.zig");

const FE0F: CodePoint = 0xfe0f;
const LAST_ASCII_CP: CodePoint = 0x7f;

pub fn filterFe0f(allocator: std.mem.Allocator, cps: []const CodePoint) ![]CodePoint {
    var result = std.ArrayList(CodePoint).init(allocator);
    defer result.deinit();
    
    for (cps) |cp| {
        if (cp != FE0F) {
            try result.append(cp);
        }
    }
    
    return result.toOwnedSlice();
}

pub fn cps2str(allocator: std.mem.Allocator, cps: []const CodePoint) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    for (cps) |cp| {
        if (cp <= 0x10FFFF) {
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(@intCast(cp), &buf) catch continue;
            try result.appendSlice(buf[0..len]);
        }
    }
    
    return result.toOwnedSlice();
}

pub fn cp2str(allocator: std.mem.Allocator, cp: CodePoint) ![]u8 {
    return cps2str(allocator, &[_]CodePoint{cp});
}

pub fn str2cps(allocator: std.mem.Allocator, str: []const u8) ![]CodePoint {
    var result = std.ArrayList(CodePoint).init(allocator);
    defer result.deinit();
    
    const utf8_view = std.unicode.Utf8View.init(str) catch return error.InvalidUtf8;
    var iter = utf8_view.iterator();
    
    while (iter.nextCodepoint()) |cp| {
        try result.append(cp);
    }
    
    return result.toOwnedSlice();
}

pub fn isAscii(cp: CodePoint) bool {
    return cp <= LAST_ASCII_CP;
}

// Note: For NFC/NFD normalization, we would need to implement Unicode normalization
// For now, these are placeholder functions that would need proper implementation
pub fn nfc(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    // This is a placeholder - would need proper Unicode NFC implementation
    return allocator.dupe(u8, str);
}

pub fn nfdCps(allocator: std.mem.Allocator, cps: []const CodePoint, specs: anytype) ![]CodePoint {
    var result = std.ArrayList(CodePoint).init(allocator);
    defer result.deinit();
    
    for (cps) |cp| {
        if (specs.decompose(cp)) |decomposed| {
            try result.appendSlice(decomposed);
        } else {
            try result.append(cp);
        }
    }
    
    return result.toOwnedSlice();
}

test "filterFe0f" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const input = [_]CodePoint{ 0x41, FE0F, 0x42, FE0F, 0x43 };
    const result = try filterFe0f(allocator, &input);
    
    const expected = [_]CodePoint{ 0x41, 0x42, 0x43 };
    try testing.expectEqualSlices(CodePoint, &expected, result);
}

test "isAscii" {
    const testing = std.testing;
    try testing.expect(isAscii(0x41)); // 'A'
    try testing.expect(isAscii(0x7F)); // DEL
    try testing.expect(!isAscii(0x80)); // beyond ASCII
    try testing.expect(!isAscii(0x1F600)); // emoji
}