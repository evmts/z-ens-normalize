const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");

test "NFC normalization debugging - café" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test case that's failing: café expected vs café got
    const input = "café";
    std.debug.print("\n=== NFC Debug: café ===\n", .{});
    std.debug.print("Input: {s}\n", .{input});
    std.debug.print("Input bytes: ", .{});
    for (input) |byte| {
        std.debug.print("{x:02} ", .{byte});
    }
    std.debug.print("\n", .{});
    
    // Test with full normalizer first to see the issue
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input) catch |err| {
        std.debug.print("Normalization error: {}\n", .{err});
        return err;
    };
    defer allocator.free(result);
    
    std.debug.print("Full normalizer result: {s}\n", .{result});
    std.debug.print("Result bytes: ", .{});
    for (result) |byte| {
        std.debug.print("{x:02} ", .{byte});
    }
    std.debug.print("\n");
    
    // Compare byte by byte
    std.debug.print("\nByte comparison:\n");
    const min_len = @min(input.len, result.len);
    for (0..min_len) |i| {
        if (input[i] != result[i]) {
            std.debug.print("Diff at byte {}: input={x:02} result={x:02}\n", .{i, input[i], result[i]});
        }
    }
    if (input.len != result.len) {
        std.debug.print("Length diff: input={} result={}\n", .{input.len, result.len});
    }
}

test "NFC normalization debugging - мой" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test case that's failing: мой
    const input = "мой";
    std.debug.print("\n=== NFC Debug: мой ===\n", .{});
    std.debug.print("Input: {s}\n", .{input});
    std.debug.print("Input bytes: ", .{});
    for (input) |byte| {
        std.debug.print("{x:02} ", .{byte});
    }
    std.debug.print("\n", .{});
    
    // Test with full normalizer
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input) catch |err| {
        std.debug.print("Normalization error: {}\n", .{err});
        return err;
    };
    defer allocator.free(result);
    
    std.debug.print("Full normalizer result: {s}\n", .{result});
    std.debug.print("Result bytes: ", .{});
    for (result) |byte| {
        std.debug.print("{x:02} ", .{byte});
    }
    std.debug.print("\n");
}

test "Empty string validation debugging" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const input = "";
    std.debug.print("\n=== Empty String Debug ===\n", .{});
    std.debug.print("Input: '{s}' (length: {})\n", .{input, input.len});
    
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input);
    if (result) |norm| {
        defer allocator.free(norm);
        std.debug.print("ERROR: Empty string should fail but got: '{s}'\n", .{norm});
        return error.TestFailure;
    } else |err| {
        std.debug.print("Correctly failed with error: {}\n", .{err});
    }
}

test "Dot validation debugging" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const input = ".";
    std.debug.print("\n=== Dot Validation Debug ===\n", .{});
    std.debug.print("Input: '{s}'\n", .{input});
    
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    const result = normalizer.normalize(input);
    if (result) |norm| {
        defer allocator.free(norm);
        std.debug.print("ERROR: Single dot should fail but got: '{s}'\n", .{norm});
        return error.TestFailure;
    } else |err| {
        std.debug.print("Correctly failed with error: {}\n", .{err});
    }
}