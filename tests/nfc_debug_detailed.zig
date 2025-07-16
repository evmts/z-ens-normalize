const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");
const tokenizer = ens_normalize.tokenizer;
const code_points = ens_normalize.code_points;
const static_data_loader = ens_normalize.static_data_loader;

test "debug NFC detailed step by step" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const combining = "cafe\u{0301}"; // café with combining acute accent
    std.debug.print("\n=== DETAILED NFC DEBUG ===\n", .{});
    std.debug.print("Input: '{s}'\n", .{combining});
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Step 1: Check what happens in tokenization with NFC enabled
    std.debug.print("\n1. Tokenizing with apply_nfc=true...\n", .{});
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, combining, &specs, true);
    defer tokenized.deinit();
    
    std.debug.print("   Result: {} tokens\n", .{tokenized.tokens.len});
    for (tokenized.tokens, 0..) |token, i| {
        std.debug.print("   Token[{}]: {s} ", .{i, @tagName(token.type)});
        const cps = token.getCps();
        std.debug.print("cps=[", .{});
        for (cps, 0..) |cp, j| {
            if (j > 0) std.debug.print(", ", .{});
            std.debug.print("U+{X:0>4}", .{cp});
        }
        std.debug.print("]\n", .{});
    }
    
    // Step 2: Check NFC data loading
    std.debug.print("\n2. Testing NFC data loading...\n", .{});
    const nfc_data = static_data_loader.loadNFC(allocator) catch |err| {
        std.debug.print("   ❌ Failed to load NFC data: {}\n", .{err});
        return;
    };
    defer nfc_data.deinit();
    std.debug.print("   ✅ NFC data loaded successfully\n", .{});
    
    // Step 3: Check if U+0301 needs NFC checking
    std.debug.print("\n3. Checking if U+0301 needs NFC...\n", .{});
    const needs_nfc = nfc_data.requiresNFCCheck(0x0301);
    std.debug.print("   U+0301 requiresNFCCheck: {}\n", .{needs_nfc});
    
    // Step 4: Manual NFC test
    std.debug.print("\n4. Manual NFC test...\n", .{});
    const test_cps = [_]u32{0x0065, 0x0301}; // e + combining acute
    const nfc_result = ens_normalize.nfc.nfc(allocator, &test_cps, &nfc_data) catch |err| {
        std.debug.print("   ❌ NFC failed: {}\n", .{err});
        return;
    };
    defer allocator.free(nfc_result);
    
    std.debug.print("   Input: [U+0065, U+0301]\n", .{});
    std.debug.print("   NFC result: [", .{});
    for (nfc_result, 0..) |cp, i| {
        if (i > 0) std.debug.print(", ", .{});
        std.debug.print("U+{X:0>4}", .{cp});
    }
    std.debug.print("]\n", .{});
    
    const expected_e_acute = 0x00E9;
    if (nfc_result.len == 1 and nfc_result[0] == expected_e_acute) {
        std.debug.print("   ✅ NFC working correctly: e + combining acute → é\n", .{});
    } else {
        std.debug.print("   ❌ NFC not working as expected\n", .{});
    }
}