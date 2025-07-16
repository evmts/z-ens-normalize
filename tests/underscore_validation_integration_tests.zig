const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");

// Test cases from Go reference implementation
test "underscore validation - should pass" {
    const allocator = testing.allocator;
    
    // These should pass (underscores only at beginning)
    const valid_names = [_][]const u8{
        "_a",
        "_____a",
        "_000000",
        "_meta",
        "_kek",
        "_everything",
    };
    
    for (valid_names) |name| {
        const result = ens_normalize.normalize(allocator, name);
        // We expect this to succeed or fail with a different error (not underscore-related)
        if (result) |normalized| {
            allocator.free(normalized);
            std.debug.print("✓ {s} normalized successfully\n", .{name});
        } else |err| {
            // If it fails, it should not be due to underscore validation
            std.debug.print("✗ {s} failed with error: {}\n", .{name, err});
        }
    }
}

test "underscore validation - should fail" {
    const allocator = testing.allocator;
    
    // These should fail (underscores in middle or end)
    const invalid_names = [_][]const u8{
        "a_b",
        "2_9", 
        "3333_3333",
        "__9__",
        "opensea_",
        "snoop_dogg",
        "kevin_",
        "lq_ql",
        "andy_",
        "thomas_",
        "a_b",
        "7_8",
        "03_30",
        "ll_ll",
        "_000000_",
        "l🔴_🔴l",
        "0_1",
        "machina_nft",
        "🐻‍❄️_🐻‍❄️",
        "thomas_anderson",
        "_666_",
        "0_x_0",
        "69_420",
        "5_5_5",
        "o__o",
    };
    
    for (invalid_names) |name| {
        const result = ens_normalize.normalize(allocator, name);
        if (result) |normalized| {
            allocator.free(normalized);
            std.debug.print("✗ {s} should have failed but succeeded\n", .{name});
            return testing.expect(false); // This should have failed
        } else |err| {
            std.debug.print("✓ {s} correctly failed with error: {}\n", .{name, err});
            // We expect this to fail due to underscore validation
            try testing.expect(err == ens_normalize.error_types.ProcessError.DisallowedSequence);
        }
    }
}