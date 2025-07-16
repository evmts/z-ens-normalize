const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test the exact same input as the failing test
    const input = "👍\u{0300}"; // thumbs up emoji + combining grave accent
    
    std.debug.print("Testing input: '{s}' (len={})\n", .{input, input.len});
    
    // Manually print the bytes
    std.debug.print("Input bytes: ", .{});
    for (input) |byte| {
        std.debug.print("{X:0>2} ", .{byte});
    }
    std.debug.print("\n", .{});
    
    var normalizer = ens_normalize.EnsNameNormalizer.init(allocator) catch |err| {
        std.debug.print("Failed to initialize normalizer: {}\n", .{err});
        return;
    };
    defer normalizer.deinit();
    
    // Try tokenizing first
    std.debug.print("Attempting to tokenize...\n", .{});
    const tokenized = normalizer.tokenize(input) catch |err| {
        std.debug.print("Tokenization failed: {}\n", .{err});
        return;
    };
    defer tokenized.deinit();
    
    std.debug.print("Tokenized successfully! {} tokens\n", .{tokenized.tokens.len});
    
    for (tokenized.tokens, 0..) |token, i| {
        std.debug.print("Token[{}]: type={s}, codepoints.len={}, emoji={}\n", .{
            i, @tagName(token.type), token.codepoints.len, token.emoji != null
        });
    }
    
    // Now try processing
    std.debug.print("Attempting to process...\n", .{});
    const processed = normalizer.process(input) catch |err| {
        std.debug.print("Processing failed: {}\n", .{err});
        return;
    };
    defer processed.deinit();
    
    std.debug.print("Processed successfully! {} labels\n", .{processed.labels.len});
    
    // Try normalization
    std.debug.print("Attempting to normalize...\n", .{});
    const result = normalizer.normalize(input) catch |err| {
        std.debug.print("Normalization failed: {}\n", .{err});
        return;
    };
    defer allocator.free(result);
    
    std.debug.print("Normalized successfully! Result: '{s}'\n", .{result});
}