const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Disable debug logging for cleaner output
    ens.logger.setLogLevel(.err);
    
    var normalizer = try ens.normalizer.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    // Test 1: Single label
    {
        const input = "hello";
        const processed = try normalizer.process(input);
        defer processed.deinit();
        
        std.debug.print("Test 1 - Single label 'hello': {} labels\n", .{processed.labels.len});
        if (processed.labels.len != 1) {
            std.debug.print("  FAIL: Expected 1 label, got {}\n", .{processed.labels.len});
        } else {
            std.debug.print("  PASS\n", .{});
        }
    }
    
    // Test 2: Two labels
    {
        const input = "hello.eth";
        const processed = try normalizer.process(input);
        defer processed.deinit();
        
        std.debug.print("Test 2 - Two labels 'hello.eth': {} labels\n", .{processed.labels.len});
        if (processed.labels.len != 2) {
            std.debug.print("  FAIL: Expected 2 labels, got {}\n", .{processed.labels.len});
        } else {
            std.debug.print("  PASS\n", .{});
        }
    }
    
    // Test 3: Three labels
    {
        const input = "sub.domain.eth";
        const processed = try normalizer.process(input);
        defer processed.deinit();
        
        std.debug.print("Test 3 - Three labels 'sub.domain.eth': {} labels\n", .{processed.labels.len});
        if (processed.labels.len != 3) {
            std.debug.print("  FAIL: Expected 3 labels, got {}\n", .{processed.labels.len});
        } else {
            std.debug.print("  PASS\n", .{});
        }
    }
    
    // Test 4: Empty label should fail
    {
        const input = "hello..eth";
        const result = normalizer.process(input);
        if (result) |processed| {
            processed.deinit();
            std.debug.print("Test 4 - Empty label 'hello..eth': FAIL - Should have failed\n", .{});
        } else |_| {
            std.debug.print("Test 4 - Empty label 'hello..eth': PASS - Failed as expected\n", .{});
        }
    }
    
    // Test 5: Normalized output preserves dots
    {
        const input = "hello.world.eth";
        const normalized = try normalizer.normalize(input);
        defer allocator.free(normalized);
        
        std.debug.print("Test 5 - Normalized 'hello.world.eth': '{s}'\n", .{normalized});
        if (std.mem.eql(u8, normalized, "hello.world.eth")) {
            std.debug.print("  PASS\n", .{});
        } else {
            std.debug.print("  FAIL: Expected 'hello.world.eth'\n", .{});
        }
    }
}