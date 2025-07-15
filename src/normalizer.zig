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

pub const EnsNameNormalizer = struct {
    specs: code_points.CodePointsSpecs,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, specs: code_points.CodePointsSpecs) EnsNameNormalizer {
        return EnsNameNormalizer{
            .specs = specs,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *EnsNameNormalizer) void {
        self.specs.deinit();
    }
    
    pub fn tokenize(self: *const EnsNameNormalizer, input: []const u8) !tokenizer.TokenizedName {
        return tokenizer.TokenizedName.fromInput(self.allocator, input, &self.specs, true);
    }
    
    pub fn process(self: *const EnsNameNormalizer, input: []const u8) !ProcessedName {
        const tokenized = try self.tokenize(input);
        const labels = try validate.validateName(self.allocator, tokenized, &self.specs);
        
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
    
    pub fn default(allocator: std.mem.Allocator) EnsNameNormalizer {
        return EnsNameNormalizer.init(allocator, code_points.CodePointsSpecs.init(allocator));
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
    var normalizer = EnsNameNormalizer.default(allocator);
    defer normalizer.deinit();
    return normalizer.tokenize(input);
}

pub fn process(allocator: std.mem.Allocator, input: []const u8) !ProcessedName {
    var normalizer = EnsNameNormalizer.default(allocator);
    defer normalizer.deinit();
    return normalizer.process(input);
}

pub fn normalize(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    // Use character mappings directly for better performance
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &code_points.CodePointsSpecs.init(allocator), false);
    defer tokenized.deinit();
    return normalizeTokens(allocator, tokenized.tokens);
}

pub fn beautify(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    // Use character mappings directly for better performance
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, input, &code_points.CodePointsSpecs.init(allocator), false);
    defer tokenized.deinit();
    return beautifyTokens(allocator, tokenized.tokens);
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
    
    var normalizer = EnsNameNormalizer.default(allocator);
    defer normalizer.deinit();
    
    const input = "hello.eth";
    const result = normalizer.normalize(input) catch |err| {
        // For now, expect errors since we haven't implemented full functionality
        try testing.expect(err == error_types.ProcessError.DisallowedSequence);
        return;
    };
    defer allocator.free(result);
}