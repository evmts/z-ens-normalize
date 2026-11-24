const std = @import("std");
const ens = @import("z_ens_normalize");

fn load(result: *?*const ens.Ensip15) void {
    const instance = ens.shared();
    const allocator = std.heap.page_allocator;
    const normalized = instance.normalize(allocator, "Nick.ETH") catch return;
    defer allocator.free(normalized);
    if (std.mem.eql(u8, normalized, "nick.eth")) result.* = instance;
}

test "concurrent first callers see the same initialized singleton" {
    var results: [8]?*const ens.Ensip15 = @splat(null);
    var threads: [results.len]std.Thread = undefined;
    var spawned: usize = 0;
    errdefer for (threads[0..spawned]) |thread| thread.join();
    for (&threads, &results) |*thread, *result| {
        thread.* = try std.Thread.spawn(.{}, load, .{result});
        spawned += 1;
    }
    for (threads) |thread| thread.join();
    spawned = 0;

    const shared = ens.shared();
    for (results) |result| try std.testing.expectEqual(shared, result);
}
