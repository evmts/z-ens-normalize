const std = @import("std");
const ens = @import("ens_normalize");

pub fn main() !void {
    std.debug.print("Starting direct tokenization test...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Initialize components individually
    var specs = ens.code_points.CodePointsSpecs.init(allocator);
    defer specs.deinit();
    
    var char_mappings = try ens.static_data_loader.loadCharacterMappings(allocator);
    defer char_mappings.deinit();
    
    std.debug.print("Loading emoji map...\n", .{});
    var emoji_map = try ens.static_data_loader.loadEmoji(allocator);
    defer emoji_map.deinit();
    std.debug.print("Emoji map loaded with {} emojis\n", .{emoji_map.all_emojis.items.len});
    
    var nfc_data = try ens.static_data_loader.loadNFC(allocator);
    defer nfc_data.deinit();
    
    // Test cases
    const test_cases = [_]struct {
        input: []const u8,
        name: []const u8,
    }{
        .{ .input = "eth", .name = "simple ascii" },
        .{ .input = "ETH", .name = "uppercase" },
        .{ .input = "test123", .name = "alphanumeric" },
        .{ .input = "hello.world", .name = "with dot" },
        .{ .input = "café", .name = "with accent" },
        .{ .input = "❤️", .name = "emoji heart" },
        .{ .input = "👍", .name = "emoji thumbs" },
    };
    
    for (test_cases) |tc| {
        std.debug.print("\n=== Testing: {s} ===\n", .{tc.name});
        std.debug.print("Input: '{s}' (", .{tc.input});
        for (tc.input) |byte| {
            std.debug.print("{x:0>2} ", .{byte});
        }
        std.debug.print(")\n", .{});
        
        const tokenized = ens.tokenizer.StreamTokenizedName.fromInputWithData(
            allocator,
            tc.input,
            &specs,
            &char_mappings,
            &emoji_map,
            &nfc_data,
            false
        ) catch |err| {
            std.debug.print("Error: {}\n", .{err});
            continue;
        };
        defer tokenized.deinit();
        
        std.debug.print("Got {} tokens:\n", .{tokenized.tokens.len});
        for (tokenized.tokens, 0..) |token, i| {
            std.debug.print("  Token[{}]: type={s}, {} codepoints", .{i, @tagName(token.type), token.codepoints.len});
            if (token.isEmoji()) {
                std.debug.print(" (emoji)", .{});
            }
            std.debug.print("\n    Codepoints: ", .{});
            for (token.codepoints, 0..) |cp, j| {
                if (j > 0) std.debug.print(", ", .{});
                if (cp >= 32 and cp <= 126) {
                    std.debug.print("'{c}'", .{@as(u8, @intCast(cp))});
                } else {
                    std.debug.print("U+{X:0>4}", .{cp});
                }
            }
            std.debug.print("\n", .{});
        }
    }
    
    std.debug.print("\nTest complete\n", .{});
}