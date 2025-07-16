const std = @import("std");
const root = @import("ens_normalize");

// C-compatible exports
export fn ens_normalize(input: [*c]const u8, input_len: usize, output: [*c]u8, output_len: *usize) c_int {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const input_slice = input[0..input_len];
    
    const result = root.normalize(allocator, input_slice) catch |err| {
        switch (err) {
            error.OutOfMemory => return -1,
            else => return -3,
        }
    };
    defer allocator.free(result);
    
    if (result.len > output_len.*) {
        output_len.* = result.len;
        return -4; // Buffer too small
    }
    
    @memcpy(output[0..result.len], result);
    output_len.* = result.len;
    
    return 0; // Success
}

export fn ens_beautify(input: [*c]const u8, input_len: usize, output: [*c]u8, output_len: *usize) c_int {
    const allocator = std.heap.c_allocator;
    
    const input_slice = input[0..input_len];
    
    const result = root.beautify_fn(allocator, input_slice) catch |err| {
        switch (err) {
            error.OutOfMemory => return -1,
            else => return -3,
        }
    };
    defer allocator.free(result);
    
    if (result.len > output_len.*) {
        output_len.* = result.len;
        return -4; // Buffer too small
    }
    
    @memcpy(output[0..result.len], result);
    output_len.* = result.len;
    
    return 0; // Success
}

export fn ens_process(input: [*c]const u8, input_len: usize, normalized: [*c]u8, normalized_len: *usize, beautified: [*c]u8, beautified_len: *usize) c_int {
    const allocator = std.heap.c_allocator;
    
    const input_slice = input[0..input_len];
    
    const result = root.process(allocator, input_slice) catch |err| {
        switch (err) {
            error.OutOfMemory => return -1,
            else => return -3,
        }
    };
    defer result.deinit();
    
    // Generate normalized result
    const normalized_result = result.normalize() catch |err| {
        switch (err) {
            error.OutOfMemory => return -1,
        }
    };
    defer allocator.free(normalized_result);
    
    // Generate beautified result
    const beautified_result = result.beautify() catch |err| {
        switch (err) {
            error.OutOfMemory => return -1,
        }
    };
    defer allocator.free(beautified_result);
    
    // Copy normalized result
    if (normalized_result.len > normalized_len.*) {
        normalized_len.* = normalized_result.len;
        return -4; // Normalized buffer too small
    }
    @memcpy(normalized[0..normalized_result.len], normalized_result);
    normalized_len.* = normalized_result.len;
    
    // Copy beautified result
    if (beautified_result.len > beautified_len.*) {
        beautified_len.* = beautified_result.len;
        return -5; // Beautified buffer too small
    }
    @memcpy(beautified[0..beautified_result.len], beautified_result);
    beautified_len.* = beautified_result.len;
    
    return 0; // Success
}