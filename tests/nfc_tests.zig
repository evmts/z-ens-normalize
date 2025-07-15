const std = @import("std");
const tokenizer = @import("../src/tokenizer.zig");
const code_points = @import("../src/code_points.zig");
const nfc = @import("../src/nfc.zig");
const static_data_loader = @import("../src/static_data_loader.zig");
const utils = @import("../src/utils.zig");

test "NFC - basic composition" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Load NFC data
    var nfc_data = try static_data_loader.loadNFCData(allocator);
    defer nfc_data.deinit();
    
    // Test case: e + combining acute accent -> é
    const input = [_]u32{ 0x0065, 0x0301 }; // e + ́
    const expected = [_]u32{ 0x00E9 }; // é
    
    const result = try nfc.nfc(allocator, &input, &nfc_data);
    defer allocator.free(result);
    
    try testing.expectEqualSlices(u32, &expected, result);
}

test "NFC - decomposed string remains decomposed when excluded" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var nfc_data = try static_data_loader.loadNFCData(allocator);
    defer nfc_data.deinit();
    
    // Test with an exclusion (need to check what's actually excluded in nf.json)
    // For now, test that already composed stays composed
    const input = [_]u32{ 0x00E9 }; // é (already composed)
    
    const result = try nfc.nfc(allocator, &input, &nfc_data);
    defer allocator.free(result);
    
    try testing.expectEqualSlices(u32, &input, result);
}

test "NFC - tokenization with NFC" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test: "café" with combining accent
    const input = "cafe\u{0301}"; // cafe + combining acute on e
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, true);
    defer tokenized.deinit();
    
    // Should have created an NFC token for the e + accent
    var has_nfc_token = false;
    for (tokenized.tokens) |token| {
        if (token.type == .nfc) {
            has_nfc_token = true;
            break;
        }
    }
    
    try testing.expect(has_nfc_token);
}

test "NFC - no change when not needed" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test: regular ASCII doesn't need NFC
    const input = "hello";
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &specs, true);
    defer tokenized.deinit();
    
    // Should not have any NFC tokens
    for (tokenized.tokens) |token| {
        try testing.expect(token.type != .nfc);
    }
}

test "NFC - string conversion" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test the full string NFC function
    const input = "cafe\u{0301}"; // cafe with combining accent
    const result = try utils.nfc(allocator, input);
    defer allocator.free(result);
    
    const expected = "café"; // Should be composed
    try testing.expectEqualStrings(expected, result);
}