const std = @import("std");
const ens = @import("z_ens_normalize");
const allocator = std.testing.allocator;

fn checkName(input: []const u8) !void {
    const normalized = ens.normalize(allocator, input) catch |err| {
        if (err == error.OutOfMemory) return err;
        try std.testing.expectError(err, ens.beautify(allocator, input));
        return;
    };
    defer allocator.free(normalized);
    try std.testing.expect(std.unicode.utf8ValidateSlice(normalized));

    const repeated = try ens.normalize(allocator, normalized);
    defer allocator.free(repeated);
    try std.testing.expectEqualStrings(normalized, repeated);

    const beautiful = try ens.beautify(allocator, input);
    defer allocator.free(beautiful);
    const canonical = try ens.normalize(allocator, beautiful);
    defer allocator.free(canonical);
    try std.testing.expectEqualStrings(normalized, canonical);
}

test "normalization properties over generated ENS labels and arbitrary bytes" {
    const fragments = [_][]const u8{ "ABC", "0", "-", "_", ".", "eth", "é", "e\u{301}", "ξ", "猫", "🏴‍☠️", "\u{200d}", "\u{00ad}" };
    var prng = std.Random.DefaultPrng.init(0x454e5349503135);
    const random = prng.random();
    var buffer: [128]u8 = undefined;

    for (0..4096) |_| {
        const raw = buffer[0..random.intRangeAtMost(usize, 0, buffer.len)];
        random.bytes(raw);
        try checkName(raw);

        var len: usize = 0;
        for (0..random.intRangeAtMost(usize, 0, 8)) |_| {
            const fragment = fragments[random.uintLessThan(usize, fragments.len)];
            @memcpy(buffer[len..][0..fragment.len], fragment);
            len += fragment.len;
        }
        try checkName(buffer[0..len]);
    }
}

test "normalization cleans up after allocation failure" {
    _ = ens.shared();
    try std.testing.checkAllAllocationFailures(allocator, normalizeWithAllocator, .{});
}

fn normalizeWithAllocator(test_allocator: std.mem.Allocator) !void {
    const result = try ens.normalize(test_allocator, "🏴‍☠️.café.eth");
    defer test_allocator.free(result);
    try std.testing.expectEqualStrings("🏴‍☠.café.eth", result);
}

test "truncated UTF-8 returns a validation error" {
    try std.testing.expectError(error.InvalidUtf8, ens.normalize(allocator, "a\xe2\x82"));
}
