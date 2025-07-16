const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");
const tokenizer = ens_normalize.tokenizer;
const validator = ens_normalize.validator;
const code_points = ens_normalize.code_points;

test "debug hello.eth step by step" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const input = "hello.eth";
    std.debug.print("\n=== DEBUGGING: '{s}' ===\n", .{input});
    
    // Step 1: Try direct normalize call
    std.debug.print("1. Trying ens_normalize.normalize()...\n", .{});
    const normalize_result = ens_normalize.normalize(allocator, input) catch |err| {
        std.debug.print("   ❌ normalize() failed: {}\n", .{err});
        
        // Step 2: Debug tokenization
        std.debug.print("2. Debugging tokenization...\n", .{});
        const specs = code_points.CodePointsSpecs.init(allocator);
        const tokenized = tokenizer.TokenizedName.fromInput(allocator, input, &specs, false) catch |token_err| {
            std.debug.print("   ❌ Tokenization failed: {}\n", .{token_err});
            return;
        };
        defer tokenized.deinit();
        
        std.debug.print("   ✅ Tokenization succeeded: {} tokens\n", .{tokenized.tokens.len});
        for (tokenized.tokens, 0..) |token, i| {
            std.debug.print("     Token[{}]: {s}", .{i, @tagName(token.type)});
            switch (token.type) {
                .disallowed => std.debug.print(" (cp=0x{x})", .{token.data.disallowed.cp}),
                .stop => std.debug.print(" (cp=0x{x})", .{token.data.stop.cp}),
                else => {},
            }
            std.debug.print("\n", .{});
        }
        
        // Step 3: Debug validation
        std.debug.print("3. Debugging validation...\n", .{});
        const validation_result = validator.validateLabel(allocator, tokenized, &specs) catch |val_err| {
            std.debug.print("   ❌ Validation failed: {}\n", .{val_err});
            return;
        };
        defer validation_result.deinit();
        
        std.debug.print("   ✅ Validation succeeded\n", .{});
        return;
    };
    defer allocator.free(normalize_result);
    
    std.debug.print("   ✅ normalize() succeeded: '{s}'\n", .{normalize_result});
}