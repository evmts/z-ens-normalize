const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    
    // Test cases from the reference tests showing beautify behavior
    const test_cases = [_]struct {
        input: []const u8,
        normalized: []const u8,
        description: []const u8,
    }{
        // Greek xi cases - when NOT in Greek script context, ξ => Ξ
        .{ .input = "Ξcoin", .normalized = "ξcoin", .description = "Uppercase Xi to lowercase in normalize" },
        .{ .input = "ξcoin", .normalized = "ξcoin", .description = "Lowercase xi stays lowercase in normalize" },
        .{ .input = "ΞETH", .normalized = "ξeth", .description = "Xi with uppercase letters" },
        .{ .input = "mΞrge", .normalized = "mξrge", .description = "Xi in middle of word" },
        .{ .input = "porschΞ911", .normalized = "porschξ911", .description = "Xi in middle with numbers" },
        
        // Emoji cases - beautify removes variation selectors
        .{ .input = "✨", .normalized = "✨", .description = "Sparkles emoji without VS" },
        .{ .input = "✨️", .normalized = "✨", .description = "Sparkles emoji with VS-16 removed" },
        .{ .input = "🌺", .normalized = "🌺", .description = "Hibiscus emoji without VS" },
        .{ .input = "🌺️", .normalized = "🌺", .description = "Hibiscus emoji with VS-16 removed" },
        .{ .input = "💸", .normalized = "💸", .description = "Money with wings emoji without VS" },
        .{ .input = "💸️", .normalized = "💸", .description = "Money with wings emoji with VS-16 removed" },
        .{ .input = "🎈", .normalized = "🎈", .description = "Balloon emoji without VS" },
        .{ .input = "🎈️", .normalized = "🎈", .description = "Balloon emoji with VS-16 removed" },
        
        // Keycap sequences
        .{ .input = "ξ6️⃣9️⃣", .normalized = "ξ6⃣9⃣", .description = "Xi with keycap sequences - VS removed" },
        .{ .input = "Ξ7️⃣7️⃣7️⃣7️⃣", .normalized = "ξ7⃣7⃣7⃣7⃣", .description = "Xi with multiple keycaps - VS removed" },
    };
    
    std.debug.print("\n=== Normalize vs Beautify Test Cases ===\n\n", .{});
    
    for (test_cases) |tc| {
        std.debug.print("Input: \"{s}\"\n", .{tc.input});
        std.debug.print("Expected normalized: \"{s}\"\n", .{tc.normalized});
        std.debug.print("Description: {s}\n", .{tc.description});
        
        // Test normalize
        const normalized = try ens_normalize.normalize(allocator, tc.input);
        defer allocator.free(normalized);
        
        std.debug.print("Actual normalized: \"{s}\" ", .{normalized});
        if (std.mem.eql(u8, normalized, tc.normalized)) {
            std.debug.print("✓\n", .{});
        } else {
            std.debug.print("✗ MISMATCH!\n", .{});
        }
        
        // Test beautify
        const beautified = try ens_normalize.beautify_fn(allocator, tc.input);
        defer allocator.free(beautified);
        
        std.debug.print("Beautified: \"{s}\"\n", .{beautified});
        
        // For beautify, we expect:
        // 1. If input contains ξ (lowercase xi), it should become Ξ (uppercase Xi) in non-Greek context
        // 2. If input contains Ξ (uppercase Xi), it should stay as Ξ
        // 3. Emojis should keep their visual form but may have VS removed
        
        std.debug.print("\n", .{});
    }
    
    // Special test: Greek script context
    std.debug.print("=== Greek Script Context Test ===\n\n", .{});
    
    // In a pure Greek context, ξ should remain ξ in beautify
    const greek_tests = [_]struct {
        input: []const u8,
        description: []const u8,
    }{
        .{ .input = "ξένος", .description = "Greek word 'xenos' - xi should stay lowercase" },
        .{ .input = "αλέξανδρος", .description = "Greek name 'alexandros'" },
        .{ .input = "ξυλόφωνο", .description = "Greek word 'xylophone' - xi should stay lowercase" },
    };
    
    for (greek_tests) |tc| {
        std.debug.print("Input: \"{s}\"\n", .{tc.input});
        std.debug.print("Description: {s}\n", .{tc.description});
        
        const normalized = try ens_normalize.normalize(allocator, tc.input);
        defer allocator.free(normalized);
        
        const beautified = try ens_normalize.beautify_fn(allocator, tc.input);
        defer allocator.free(beautified);
        
        std.debug.print("Normalized: \"{s}\"\n", .{normalized});
        std.debug.print("Beautified: \"{s}\"\n", .{beautified});
        std.debug.print("\n", .{});
    }
}