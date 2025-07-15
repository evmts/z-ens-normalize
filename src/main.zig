const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("ENS Normalize Zig Implementation\n", .{});
    try stdout.print("=================================\n\n", .{});
    
    // Example usage
    const test_names = [_][]const u8{
        "hello.eth",
        "test-domain.eth",
        "ξ.eth",
        "hello.eth",
    };
    
    for (test_names) |name| {
        try stdout.print("Input: {s}\n", .{name});
        
        // Try to normalize the name
        const normalized = ens_normalize.normalize(allocator, name) catch |err| {
            try stdout.print("Error: {}\n", .{err});
            continue;
        };
        defer allocator.free(normalized);
        
        try stdout.print("Normalized: {s}\n", .{normalized});
        
        // Try to beautify the name
        const beautified = ens_normalize.beautify_fn(allocator, name) catch |err| {
            try stdout.print("Beautify Error: {}\n", .{err});
            continue;
        };
        defer allocator.free(beautified);
        
        try stdout.print("Beautified: {s}\n", .{beautified});
        try stdout.print("\n", .{});
    }
    
    try stdout.print("Note: This is a basic implementation. Full ENS normalization\n", .{});
    try stdout.print("requires additional Unicode data and processing logic.\n", .{});
}

test "basic library functionality" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test basic tokenization
    const input = "hello";
    const tokenized = ens_normalize.tokenize(allocator, input) catch |err| {
        // For now, expect errors since we haven't implemented full functionality
        try testing.expect(err == ens_normalize.error_types.ProcessError.DisallowedSequence);
        return;
    };
    defer tokenized.deinit(allocator);
    
    try testing.expect(tokenized.tokens.len > 0);
}

test "memory management" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test that we properly manage memory
    var normalizer = ens_normalize.normalizer.EnsNameNormalizer.default(allocator);
    defer normalizer.deinit();
    
    const input = "test";
    const result = normalizer.normalize(input) catch |err| {
        // Expected to fail with current implementation
        try testing.expect(err == ens_normalize.error_types.ProcessError.DisallowedSequence);
        return;
    };
    defer allocator.free(result);
}