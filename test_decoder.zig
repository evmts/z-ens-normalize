const std = @import("std");
const Decoder = @import("z_ens_normalize").Decoder;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Load nf.bin
    const nf_bin = @embedFile("src/nf/nf.bin");
    var decoder = try Decoder.init(nf_bin, allocator);
    defer decoder.deinit(allocator);

    // Read version string (should be something like "15.1.0")
    const version = try decoder.ReadString(allocator);
    defer allocator.free(version);
    std.debug.print("Unicode version: {s}\n", .{version});

    // Read exclusions (first ReadUnique call)
    const exclusions = try decoder.ReadUnique(allocator);
    defer allocator.free(exclusions);
    
    std.debug.print("\nExclusions loaded: {}\n", .{exclusions.len});
    std.debug.print("First 16 exclusions:\n", .{});
    for (exclusions[0..@min(16, exclusions.len)]) |excl| {
        std.debug.print("  {d} (U+{X:0>4})\n", .{excl, excl});
    }
}
