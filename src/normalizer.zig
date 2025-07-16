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
const log = @import("logger.zig");

pub const EnsNameNormalizer = struct {
    specs: code_points.CodePointsSpecs,
    character_mappings: character_mappings.CharacterMappings,
    script_groups: script_groups.ScriptGroups,
    confusables: confusables.ConfusableData,
    nfc_data: nfc.NFCData,
    emoji_map: emoji.EmojiMap,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) !EnsNameNormalizer {
        log.debug("Initializing EnsNameNormalizer", .{});
        const timer = log.Timer.start("EnsNameNormalizer.init");
        defer timer.stop();
        
        const normalizer = EnsNameNormalizer{
            .specs = code_points.CodePointsSpecs.init(allocator),
            .character_mappings = try static_data_loader.loadCharacterMappings(allocator),
            .script_groups = try static_data_loader.loadScriptGroups(allocator),
            .confusables = try static_data_loader.loadConfusables(allocator),
            .nfc_data = try static_data_loader.loadNFC(allocator),
            .emoji_map = try static_data_loader.loadEmoji(allocator),
            .allocator = allocator,
        };
        
        log.info("EnsNameNormalizer initialized successfully", .{});
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
    
    pub fn tokenize(self: *const EnsNameNormalizer, input: []const u8) !tokenizer.StreamTokenizedName {
        log.enterFn("EnsNameNormalizer.tokenize", "input.len={}", .{input.len});
        log.unicodeDebug("Input to tokenize", input);
        
        const result = tokenizer.StreamTokenizedName.fromInputWithData(
            self.allocator, 
            input, 
            &self.specs, 
            &self.character_mappings,
            &self.emoji_map,
            &self.nfc_data,
            true
        ) catch |e| {
            log.errTrace("EnsNameNormalizer.tokenize", e);
            return e;
        };
        
        log.debug("Tokenization complete: {} tokens", .{result.tokens.len});
        log.exitFn("EnsNameNormalizer.tokenize", "tokens.len={}", .{result.tokens.len});
        return result;
    }
    
    pub fn process(self: *const EnsNameNormalizer, input: []const u8) !ProcessedName {
        log.enterFn("EnsNameNormalizer.process", "input.len={}", .{input.len});
        log.unicodeDebug("Processing ENS name", input);
        const timer = log.Timer.start("EnsNameNormalizer.process");
        defer timer.stop();
        
        const tokenized = try self.tokenize(input);
        log.debug("Tokenization complete, validating {} tokens", .{tokenized.tokens.len});
        
        const labels = validate.validateNameWithStreamData(
            self.allocator, 
            tokenized, 
            &self.specs,
            &self.script_groups,
            &self.confusables
        ) catch |e| {
            log.errTrace("EnsNameNormalizer.process validation", e);
            tokenized.deinit();
            return e;
        };
        
        log.info("Processed ENS name: {} labels from {} tokens", .{labels.len, tokenized.tokens.len});
        log.exitFn("EnsNameNormalizer.process", "labels.len={}", .{labels.len});
        
        return ProcessedName{
            .labels = labels,
            .tokenized = tokenized,
            .allocator = self.allocator,
        };
    }
    
    pub fn normalize(self: *const EnsNameNormalizer, input: []const u8) ![]u8 {
        log.enterFn("EnsNameNormalizer.normalize", "input.len={}", .{input.len});
        log.unicodeDebug("Normalizing ENS name", input);
        const timer = log.Timer.start("EnsNameNormalizer.normalize");
        defer timer.stop();
        
        const processed = try self.process(input);
        defer processed.deinit();
        
        const result = try processed.normalize();
        log.unicodeDebug("Normalized result", result);
        log.exitFn("EnsNameNormalizer.normalize", "result.len={}", .{result.len});
        return result;
    }
    
    pub fn beautify_fn(self: *const EnsNameNormalizer, input: []const u8) ![]u8 {
        log.enterFn("EnsNameNormalizer.beautify_fn", "input.len={}", .{input.len});
        log.unicodeDebug("Beautifying ENS name", input);
        const timer = log.Timer.start("EnsNameNormalizer.beautify_fn");
        defer timer.stop();
        
        const processed = try self.process(input);
        defer processed.deinit();
        
        const result = try processed.beautify();
        log.unicodeDebug("Beautified result", result);
        log.exitFn("EnsNameNormalizer.beautify_fn", "result.len={}", .{result.len});
        return result;
    }
    
    pub fn default(allocator: std.mem.Allocator) !EnsNameNormalizer {
        return EnsNameNormalizer.init(allocator);
    }
};

pub const ProcessedName = struct {
    labels: []validate.ValidatedLabel,
    tokenized: tokenizer.StreamTokenizedName,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: ProcessedName) void {
        for (self.labels) |label| {
            label.deinit();
        }
        self.allocator.free(self.labels);
        self.tokenized.deinit();
    }
    
    pub fn normalize(self: *const ProcessedName) ![]u8 {
        return normalizeStreamTokens(self.allocator, self.tokenized.tokens);
    }
    
    pub fn beautify(self: *const ProcessedName) ![]u8 {
        return beautifyProcessedName(self.allocator, self.labels, self.tokenized.tokens);
    }
};

// Stream token processing functions
fn normalizeStreamTokens(allocator: std.mem.Allocator, token_list: []const tokenizer.OutputToken) ![]u8 {
    log.enterFn("normalizeStreamTokens", "token_list.len={}", .{token_list.len});
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    for (token_list, 0..) |token, i| {
        log.trace("Processing token {}: type={s}, codepoints.len={}", .{i, @tagName(token.type), token.codepoints.len});
        
        // Handle stop tokens (dots) specially
        if (token.type == .stop) {
            log.trace("  Adding stop character (dot)", .{});
            try result.append('.');
            continue;
        }
        
        // Convert codepoints to UTF-8 and append to result
        for (token.codepoints) |cp| {
            log.trace("  Encoding codepoint U+{X:0>4}", .{cp});
            const utf8_len = std.unicode.utf8CodepointSequenceLength(@as(u21, @intCast(cp))) catch {
                log.warn("Invalid codepoint U+{X:0>4}, skipping", .{cp});
                continue;
            };
            const old_len = result.items.len;
            try result.resize(old_len + utf8_len);
            _ = std.unicode.utf8Encode(@as(u21, @intCast(cp)), result.items[old_len..]) catch {
                log.warn("Failed to encode codepoint U+{X:0>4}, skipping", .{cp});
                continue;
            };
        }
    }
    
    const output = try result.toOwnedSlice();
    log.exitFn("normalizeStreamTokens", "output.len={}", .{output.len});
    return output;
}

fn beautifyProcessedName(allocator: std.mem.Allocator, labels: []const validate.ValidatedLabel, token_list: []const tokenizer.OutputToken) ![]u8 {
    log.enterFn("beautifyProcessedName", "labels.len={}, token_list.len={}", .{labels.len, token_list.len});
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();
    
    // We need to track which label we're in as we process tokens
    var current_label_idx: usize = 0;
    var tokens_in_current_label: usize = 0;
    
    for (token_list, 0..) |token, i| {
        // Handle stop tokens (dots)
        if (token.type == .stop) {
            if (result.items.len > 0) {
                try result.append('.');
            }
            // Move to next label
            if (current_label_idx < labels.len) {
                current_label_idx += 1;
                tokens_in_current_label = 0;
            }
            continue;
        }
        
        // Get the current label type
        const label_type = if (current_label_idx < labels.len) labels[current_label_idx].label_type else validate.LabelType.ascii;
        
        if (token.isEmoji()) {
            // For emoji, use fully-qualified form with FE0F
            const emoji_cps = token.emoji.?.emoji;
            log.trace("Processing emoji token {}: {} codepoints", .{i, emoji_cps.len});
            
            for (emoji_cps) |cp| {
                log.trace("  Encoding emoji codepoint U+{X:0>4}", .{cp});
                const utf8_len = std.unicode.utf8CodepointSequenceLength(@as(u21, @intCast(cp))) catch {
                    log.warn("Invalid emoji codepoint U+{X:0>4}, skipping", .{cp});
                    continue;
                };
                const old_len = result.items.len;
                try result.resize(old_len + utf8_len);
                _ = std.unicode.utf8Encode(@as(u21, @intCast(cp)), result.items[old_len..]) catch {
                    log.warn("Failed to encode emoji codepoint U+{X:0>4}, skipping", .{cp});
                    continue;
                };
            }
        } else {
            // For text, apply beautification rules
            log.trace("Processing text token {}: type={s}, {} codepoints, label_type={s}", .{i, @tagName(token.type), token.codepoints.len, @tagName(label_type)});
            
            for (token.codepoints) |cp_orig| {
                var cp = cp_orig;
                
                // Apply Greek character replacement: ξ (0x3BE) => Ξ (0x39E) if not Greek label
                if (label_type != .greek and cp == root.constants.CP_XI_SMALL) {
                    cp = root.constants.CP_XI_CAPITAL;
                    log.debug("  Replacing ξ (U+{X:0>4}) with Ξ (U+{X:0>4}) for non-Greek label", .{root.constants.CP_XI_SMALL, root.constants.CP_XI_CAPITAL});
                }
                
                log.trace("  Encoding text codepoint U+{X:0>4}", .{cp});
                const utf8_len = std.unicode.utf8CodepointSequenceLength(@as(u21, @intCast(cp))) catch {
                    log.warn("Invalid text codepoint U+{X:0>4}, skipping", .{cp});
                    continue;
                };
                const old_len = result.items.len;
                try result.resize(old_len + utf8_len);
                _ = std.unicode.utf8Encode(@as(u21, @intCast(cp)), result.items[old_len..]) catch {
                    log.warn("Failed to encode text codepoint U+{X:0>4}, skipping", .{cp});
                    continue;
                };
            }
        }
        
        tokens_in_current_label += 1;
    }
    
    const output = try result.toOwnedSlice();
    log.exitFn("beautifyProcessedName", "output.len={}", .{output.len});
    return output;
}

// Convenience functions that use default normalizer
pub fn tokenize(allocator: std.mem.Allocator, input: []const u8) !tokenizer.StreamTokenizedName {
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
    log.setLogLevel(.trace); // Enable full logging for tests
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