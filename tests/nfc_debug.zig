const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");
const tokenizer = ens_normalize.tokenizer;
const code_points = ens_normalize.code_points;

test "debug NFC tokenization" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const combining = "cafe\u{0301}"; // café with combining acute accent
    std.debug.print("\n=== NFC TOKENIZATION DEBUG ===\n", .{});
    std.debug.print("Input: '{s}'\n", .{combining});
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test without NFC
    std.debug.print("\n1. Tokenization WITHOUT NFC:\n", .{});
    const tokenized_without_nfc = try tokenizer.TokenizedName.fromInput(allocator, combining, &specs, false);
    defer tokenized_without_nfc.deinit();
    
    std.debug.print("Tokens: {}\n", .{tokenized_without_nfc.tokens.len});
    for (tokenized_without_nfc.tokens, 0..) |token, i| {
        std.debug.print("  Token[{}]: {s}\n", .{i, @tagName(token.type)});
    }
    
    // Test with NFC
    std.debug.print("\n2. Tokenization WITH NFC:\n", .{});
    const tokenized_with_nfc = try tokenizer.TokenizedName.fromInput(allocator, combining, &specs, true);
    defer tokenized_with_nfc.deinit();
    
    std.debug.print("Tokens: {}\n", .{tokenized_with_nfc.tokens.len});
    for (tokenized_with_nfc.tokens, 0..) |token, i| {
        std.debug.print("  Token[{}]: {s}\n", .{i, @tagName(token.type)});
    }
    
    // Compare normalization output
    std.debug.print("\n3. Normalization comparison:\n", .{});
    
    const normalized_without = try ens_normalize.normalize(allocator, combining);
    defer allocator.free(normalized_without);
    std.debug.print("normalize(): '{s}'\n", .{normalized_without});
    
    // Check if we can force NFC somehow
    const beautified = try ens_normalize.beautify_fn(allocator, combining);
    defer allocator.free(beautified);
    std.debug.print("beautify(): '{s}'\n", .{beautified});
}