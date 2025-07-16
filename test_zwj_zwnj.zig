const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test cases for ZWJ and ZWNJ
    const test_cases = [_]struct {
        name: []const u8,
        input: []const u8,
        should_error: bool,
        error_msg: ?[]const u8,
    }{
        // ZWNJ (U+200C) should always be disallowed
        .{ .name = "zwnj_alone", .input = "\u{200C}", .should_error = true, .error_msg = "disallowed character" },
        .{ .name = "zwnj_in_word", .input = "te\u{200C}st", .should_error = true, .error_msg = "disallowed character" },
        .{ .name = "zwnj_leading", .input = "\u{200C}test", .should_error = true, .error_msg = "disallowed character" },
        .{ .name = "zwnj_trailing", .input = "test\u{200C}", .should_error = true, .error_msg = "disallowed character" },
        
        // ZWJ (U+200D) outside emoji should be disallowed
        .{ .name = "zwj_alone", .input = "\u{200D}", .should_error = true, .error_msg = "leading" },
        .{ .name = "zwj_in_word", .input = "te\u{200D}st", .should_error = true, .error_msg = "ZWJ" },
        .{ .name = "zwj_leading", .input = "\u{200D}test", .should_error = true, .error_msg = "leading" },
        .{ .name = "zwj_trailing", .input = "test\u{200D}", .should_error = true, .error_msg = "trailing" },
        
        // Valid emoji with ZWJ should work
        .{ .name = "family_emoji", .input = "👨‍👩‍👧‍👦", .should_error = false, .error_msg = null },
        .{ .name = "rainbow_flag", .input = "🏳️‍🌈", .should_error = false, .error_msg = null },
        
        // Normal text should work
        .{ .name = "normal_text", .input = "test", .should_error = false, .error_msg = null },
        .{ .name = "normal_emoji", .input = "😀", .should_error = false, .error_msg = null },
    };
    
    std.debug.print("=== ZWJ/ZWNJ Handling Test ===\n\n", .{});
    
    var passed: usize = 0;
    var failed: usize = 0;
    
    for (test_cases) |tc| {
        std.debug.print("Test: {s}\n", .{tc.name});
        std.debug.print("  Input: ", .{});
        
        // Print readable format
        var i: usize = 0;
        while (i < tc.input.len) {
            const len = std.unicode.utf8ByteSequenceLength(tc.input[i]) catch 1;
            if (i + len <= tc.input.len) {
                const cp = std.unicode.utf8Decode(tc.input[i..i+len]) catch 0;
                if (cp == 0x200C) {
                    std.debug.print("<ZWNJ>", .{});
                } else if (cp == 0x200D) {
                    std.debug.print("<ZWJ>", .{});
                } else if (cp < 128 and std.ascii.isPrint(@intCast(cp))) {
                    std.debug.print("{c}", .{@as(u8, @intCast(cp))});
                } else {
                    std.debug.print("{s}", .{tc.input[i..i+len]});
                }
                i += len;
            } else {
                i += 1;
            }
        }
        std.debug.print("\n", .{});
        
        const result = ens.normalize(allocator, tc.input) catch |err| {
            if (tc.should_error) {
                std.debug.print("  ✅ Expected error: {}\n", .{err});
                passed += 1;
            } else {
                std.debug.print("  ❌ Unexpected error: {}\n", .{err});
                failed += 1;
            }
            continue;
        };
        defer allocator.free(result);
        
        if (tc.should_error) {
            std.debug.print("  ❌ Expected error but got success: '{s}'\n", .{result});
            failed += 1;
        } else {
            std.debug.print("  ✅ Success: '{s}'\n", .{result});
            passed += 1;
        }
    }
    
    std.debug.print("\n=== Summary ===\n", .{});
    std.debug.print("Passed: {}/{}\n", .{passed, passed + failed});
    std.debug.print("Failed: {}\n", .{failed});
}