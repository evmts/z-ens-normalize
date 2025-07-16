const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const constants = @import("constants.zig");

const FE0F: CodePoint = 0xfe0f;
const LAST_ASCII_CP: CodePoint = 0x7f;

pub fn filterFe0f(allocator: std.mem.Allocator, cps: []const CodePoint) ![]CodePoint {
    var result = std.ArrayList(CodePoint).init(allocator);
    errdefer result.deinit(); // Only free on error
    
    for (cps) |cp| {
        if (cp != FE0F) {
            try result.append(cp);
        }
    }
    
    return result.toOwnedSlice();
}

pub fn cps2str(allocator: std.mem.Allocator, cps: []const CodePoint) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    errdefer result.deinit(); // Only free on error
    
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
    errdefer result.deinit(); // Only free on error
    
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

// NFC normalization using our implementation
pub fn nfc(allocator: std.mem.Allocator, str: []const u8) ![]u8 {
    const nfc_mod = @import("nfc.zig");
    const static_data_loader = @import("static_data_loader.zig");
    
    // Convert string to codepoints
    const cps = try str2cps(allocator, str);
    defer allocator.free(cps);
    
    // Load NFC data
    var nfc_data = try static_data_loader.loadNFCData(allocator);
    defer nfc_data.deinit();
    
    // Apply NFC normalization
    const normalized_cps = try nfc_mod.nfc(allocator, cps, &nfc_data);
    defer allocator.free(normalized_cps);
    
    // Convert back to string
    return cps2str(allocator, normalized_cps);
}

pub fn nfdCps(allocator: std.mem.Allocator, cps: []const CodePoint, specs: anytype) ![]CodePoint {
    var result = std.ArrayList(CodePoint).init(allocator);
    errdefer result.deinit(); // Only free on error
    
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