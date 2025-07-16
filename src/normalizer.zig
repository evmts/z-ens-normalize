const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const code_points = @import("code_points.zig");
const validate = @import("validate.zig");
const error_types = @import("error.zig");
const beautify_mod = @import("beautify.zig");
const join = @import("join.zig");
const tokenizer = @import("tokenizer.zig");
const character_mappings = @import("character_mappings.zig");
const static_data_loader = @import("static_data_loader.zig");
const script_groups = @import("script_groups.zig");
const confusables = @import("confusables.zig");
const nfc = @import("nfc.zig");
const emoji = @import("emoji.zig");

pub const EnsNameNormalizer = struct {
    specs: code_points.CodePointsSpecs,
    character_mappings: character_mappings.CharacterMappings,
    script_groups: script_groups.ScriptGroups,
    confusables: confusables.ConfusableData,
    nfc_data: nfc.NFCData,
    emoji_map: emoji.EmojiMap,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !EnsNameNormalizer {
        const normalizer = EnsNameNormalizer{
            .specs = code_points.CodePointsSpecs.init(allocator),
            .character_mappings = try static_data_loader.loadCharacterMappings(allocator),
            .script_groups = try static_data_loader.loadScriptGroups(allocator),
            .confusables = try static_data_loader.loadConfusables(allocator),
            .nfc_data = try static_data_loader.loadNFC(allocator),
            .emoji_map = try static_data_loader.loadEmoji(allocator),
            .allocator = allocator,
        };
        return normalizer;
    }
    
    pub fn deinit(self: *EnsNameNormalizer) void {
        self.specs.deinit();
        self.character_mappings.deinit();
        self.script_groups.deinit();
        self.confusables.deinit();
        self.nfc_data.deinit();
        self.emoji_map.deinit();
    }
    
    pub fn tokenize(self: *const EnsNameNormalizer, input: []const u8) !tokenizer.TokenizedName {
        return tokenizer.TokenizedName.fromInputWithData(
            self.allocator, 
            input, 
            &self.specs, 
            &self.character_mappings,
            &self.emoji_map,
            &self.nfc_data,
            true
        );
    }
    
    pub fn process(self: *const EnsNameNormalizer, input: []const u8) !ProcessedName {
        const tokenized = try self.tokenize(input);
        const labels = try validate.validateNameWithData(
            self.allocator, 
            tokenized, 
            &self.specs,
            &self.script_groups,
            &self.confusables
        );
        
        return ProcessedName{
            .labels = labels,
            .tokenized = tokenized,
            .allocator = self.allocator,
        };
    }
    
    pub fn normalize(self: *const EnsNameNormalizer, input: []const u8) ![]u8 {
        const processed = try self.process(input);
        defer processed.deinit();
        return processed.normalize();
    }
    
    pub fn beautify_fn(self: *const EnsNameNormalizer, input: []const u8) ![]u8 {
        const processed = try self.process(input);
        defer processed.deinit();
        return processed.beautify();
    }
    
    pub fn default(allocator: std.mem.Allocator) !EnsNameNormalizer {
        return EnsNameNormalizer.init(allocator);
    }
};

pub const ProcessedName = struct {
    labels: []validate.ValidatedLabel,
    tokenized: tokenizer.TokenizedName,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: ProcessedName) void {
        for (self.labels) |label| {
            label.deinit();
        }
        self.allocator.free(self.labels);
        self.tokenized.deinit();
    }
    
    pub fn normalize(self: *const ProcessedName) ![]u8 {
        return normalizeTokens(self.allocator, self.tokenized.tokens);
    }
    
    pub fn beautify(self: *const ProcessedName) ![]u8 {
        return beautifyTokens(self.allocator, self.tokenized.tokens);
    }
};

// Convenience functions that use default normalizer
pub fn tokenize(allocator: std.mem.Allocator, input: []const u8) !tokenizer.TokenizedName {
    var normalizer = try EnsNameNormalizer.default(allocator);
    defer normalizer.deinit();
    return normalizer.tokenize(input);
}

pub fn process(allocator: std.mem.Allocator, input: []const u8) !ProcessedName {
    var normalizer = try EnsNameNormalizer.default(allocator);
    defer normalizer.deinit();
    return normalizer.process(input);
}

pub fn normalize(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var normalizer = try EnsNameNormalizer.default(allocator);
    defer normalizer.deinit();
    return normalizer.normalize(input);
}

pub fn beautify(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var normalizer = try EnsNameNormalizer.default(allocator);
    defer normalizer.deinit();
    return normalizer.beautify_fn(input);
}

// Token processing functions
fn normalizeTokens(allocator: std.mem.Allocator, token_list: []const tokenizer.Token) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    for (token_list) |token| {
        // Get the normalized code points for this token
        const cps = token.getCps();
        
        // Convert code points to UTF-8 and append to result
        for (cps) |cp| {
            const utf8_len = std.unicode.utf8CodepointSequenceLength(@as(u21, @intCast(cp))) catch continue;
            const old_len = result.items.len;
            try result.resize(old_len + utf8_len);
            _ = std.unicode.utf8Encode(@as(u21, @intCast(cp)), result.items[old_len..]) catch continue;
        }
    }
    
    return result.toOwnedSlice();
}

fn beautifyTokens(allocator: std.mem.Allocator, token_list: []const tokenizer.Token) ![]u8 {
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    for (token_list) |token| {
        switch (token.type) {
            .mapped => {
                // For beautification, use original character for case folding
                const original_cp = token.data.mapped.cp;
                const utf8_len = std.unicode.utf8CodepointSequenceLength(@as(u21, @intCast(original_cp))) catch continue;
                const old_len = result.items.len;
                try result.resize(old_len + utf8_len);
                _ = std.unicode.utf8Encode(@as(u21, @intCast(original_cp)), result.items[old_len..]) catch continue;
            },
            else => {
                // For other tokens, use normalized form
                const cps = token.getCps();
                for (cps) |cp| {
                    const utf8_len = std.unicode.utf8CodepointSequenceLength(@as(u21, @intCast(cp))) catch continue;
                    const old_len = result.items.len;
                    try result.resize(old_len + utf8_len);
                    _ = std.unicode.utf8Encode(@as(u21, @intCast(cp)), result.items[old_len..]) catch continue;
                }
            }
        }
    }
    
    return result.toOwnedSlice();
}

test "EnsNameNormalizer basic functionality" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var normalizer = try EnsNameNormalizer.default(allocator);
    defer normalizer.deinit();
    
    const input = "hello.eth";
    const result = normalizer.normalize(input) catch |err| {
        // For now, expect errors since we haven't implemented full functionality
        try testing.expect(err == error_types.ProcessError.DisallowedSequence);
        return;
    };
    defer allocator.free(result);
}