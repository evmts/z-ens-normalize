const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const constants = @import("constants.zig");
const utils = @import("utils.zig");
const tokenizer = @import("tokenizer.zig");
const code_points = @import("code_points.zig");
const error_types = @import("error.zig");
const script_groups = @import("script_groups.zig");
const confusables = @import("confusables.zig");

pub const LabelType = union(enum) {
    ascii,
    emoji,
    greek,
    other: []const u8,
    
    pub fn format(self: LabelType, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        switch (self) {
            .ascii => try writer.print("ASCII", .{}),
            .emoji => try writer.print("Emoji", .{}),
            .greek => try writer.print("Greek", .{}),
            .other => |name| try writer.print("{s}", .{name}),
        }
    }
};

pub const ValidatedLabel = struct {
    tokens: []const tokenizer.Token,
    label_type: LabelType,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, label_tokens: []const tokenizer.Token, label_type: LabelType) !ValidatedLabel {
        const owned_tokens = try allocator.dupe(tokenizer.Token, label_tokens);
        return ValidatedLabel{
            .tokens = owned_tokens,
            .label_type = label_type,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: ValidatedLabel) void {
        self.allocator.free(self.tokens);
    }
};

pub const TokenizedLabel = struct {
    tokens: []const tokenizer.Token,
    allocator: std.mem.Allocator,
    
    pub fn isEmpty(self: TokenizedLabel) bool {
        return self.tokens.len == 0;
    }
    
    pub fn isFullyEmoji(self: TokenizedLabel) bool {
        for (self.tokens) |token| {
            if (!token.isEmoji() and !token.isIgnored()) {
                return false;
            }
        }
        return true;
    }
    
    pub fn isFullyAscii(self: TokenizedLabel) bool {
        for (self.tokens) |token| {
            const cps = token.getCps();
            for (cps) |cp| {
                if (!utils.isAscii(cp)) {
                    return false;
                }
            }
        }
        return true;
    }
    
    pub fn iterCps(self: TokenizedLabel, allocator: std.mem.Allocator) ![]CodePoint {
        var result = std.ArrayList(CodePoint).init(allocator);
        defer result.deinit();
        
        for (self.tokens) |token| {
            const cps = token.getCps();
            try result.appendSlice(cps);
        }
        
        return result.toOwnedSlice();
    }
    
    pub fn getCpsOfNotIgnoredText(self: TokenizedLabel, allocator: std.mem.Allocator) ![]CodePoint {
        var result = std.ArrayList(CodePoint).init(allocator);
        defer result.deinit();
        
        for (self.tokens) |token| {
            if (!token.isIgnored() and token.isText()) {
                const cps = try token.getCps(allocator);
                defer allocator.free(cps);
                try result.appendSlice(cps);
            }
        }
        
        return result.toOwnedSlice();
    }
};

pub fn validateName(
    allocator: std.mem.Allocator,
    name: tokenizer.TokenizedName,
    specs: *const code_points.CodePointsSpecs,
) ![]ValidatedLabel {
    if (name.tokens.len == 0) {
        return try allocator.alloc(ValidatedLabel, 0);
    }
    
    // For now, create a simple implementation that treats the entire name as one label
    // The actual implementation would need to split on stop tokens
    var labels = std.ArrayList(ValidatedLabel).init(allocator);
    defer labels.deinit();
    
    const label = TokenizedLabel{
        .tokens = name.tokens,
        .allocator = allocator,
    };
    
    const validated = try validateLabel(allocator, label, specs);
    try labels.append(validated);
    
    return labels.toOwnedSlice();
}

pub fn validateNameWithData(
    allocator: std.mem.Allocator,
    name: tokenizer.TokenizedName,
    specs: *const code_points.CodePointsSpecs,
    script_groups_data: *const script_groups.ScriptGroups,
    confusables_data: *const confusables.ConfusableData,
) ![]ValidatedLabel {
    _ = script_groups_data;
    _ = confusables_data;
    
    if (name.tokens.len == 0) {
        return try allocator.alloc(ValidatedLabel, 0);
    }
    
    // For now, create a simple implementation that treats the entire name as one label
    // The actual implementation would need to split on stop tokens
    var labels = std.ArrayList(ValidatedLabel).init(allocator);
    defer labels.deinit();
    
    const label = TokenizedLabel{
        .tokens = name.tokens,
        .allocator = allocator,
    };
    
    const validated = try validateLabel(allocator, label, specs);
    try labels.append(validated);
    
    return labels.toOwnedSlice();
}

pub fn validateNameWithStreamData(
    allocator: std.mem.Allocator,
    name: tokenizer.StreamTokenizedName,
    specs: *const code_points.CodePointsSpecs,
    script_groups_data: *const script_groups.ScriptGroups,
    confusables_data: *const confusables.ConfusableData,
) ![]ValidatedLabel {
    _ = script_groups_data;
    _ = confusables_data;
    
    if (name.tokens.len == 0) {
        return try allocator.alloc(ValidatedLabel, 0);
    }
    
    // For now, create a simple implementation that treats the entire name as one label
    // TODO: Implement proper label splitting on stop tokens
    var labels = std.ArrayList(ValidatedLabel).init(allocator);
    defer labels.deinit();
    
    // Convert OutputTokens to legacy format for validation
    // This is temporary during TASK 2 transition
    var legacy_tokens = std.ArrayList(tokenizer.Token).init(allocator);
    defer {
        for (legacy_tokens.items) |token| {
            token.deinit();
        }
        legacy_tokens.deinit();
    }
    
    for (name.tokens) |output_token| {
        if (output_token.isEmoji()) {
            // Create emoji token
            const emoji_token = try tokenizer.Token.createEmoji(
                allocator,
                output_token.codepoints,
                output_token.emoji.?.emoji,
                output_token.codepoints
            );
            try legacy_tokens.append(emoji_token);
        } else {
            // Create valid token (assuming all text is valid for now)
            const valid_token = try tokenizer.Token.createValid(allocator, output_token.codepoints);
            try legacy_tokens.append(valid_token);
        }
    }
    
    const label = TokenizedLabel{
        .tokens = legacy_tokens.items,
        .allocator = allocator,
    };
    
    const validated = try validateLabel(allocator, label, specs);
    try labels.append(validated);
    
    return labels.toOwnedSlice();
}

pub fn validateLabel(
    allocator: std.mem.Allocator,
    label: TokenizedLabel,
    specs: *const code_points.CodePointsSpecs,
) !ValidatedLabel {
    try checkNonEmpty(label);
    try checkTokenTypes(allocator, label);
    
    if (label.isFullyEmoji()) {
        return ValidatedLabel.init(allocator, label.tokens, LabelType.emoji);
    }
    
    try checkUnderscoreOnlyAtBeginning(allocator, label);
    
    if (label.isFullyAscii()) {
        try checkNoHyphenAtSecondAndThird(allocator, label);
        return ValidatedLabel.init(allocator, label.tokens, LabelType.ascii);
    }
    
    try checkFenced(allocator, label, specs);
    try checkCmLeadingEmoji(allocator, label, specs);
    
    const group = try checkAndGetGroup(allocator, label, specs);
    _ = group; // TODO: determine actual group type
    
    // For now, return a placeholder
    return ValidatedLabel.init(allocator, label.tokens, LabelType{ .other = "Unknown" });
}

fn checkNonEmpty(label: TokenizedLabel) !void {
    var has_non_ignored = false;
    for (label.tokens) |token| {
        if (!token.isIgnored()) {
            has_non_ignored = true;
            break;
        }
    }
    
    if (!has_non_ignored) {
        return error_types.ProcessError.DisallowedSequence;
    }
}

fn checkTokenTypes(_: std.mem.Allocator, label: TokenizedLabel) !void {
    for (label.tokens) |token| {
        if (token.isDisallowed() or token.isStop()) {
            const cps = token.getCps();
            
            // Check for invisible characters
            for (cps) |cp| {
                if (cp == constants.CP_ZERO_WIDTH_JOINER or cp == constants.CP_ZERO_WIDTH_NON_JOINER) {
                    return error_types.ProcessError.DisallowedSequence;
                }
            }
            
            return error_types.ProcessError.DisallowedSequence;
        }
    }
}

fn checkUnderscoreOnlyAtBeginning(allocator: std.mem.Allocator, label: TokenizedLabel) !void {
    const cps = try label.iterCps(allocator);
    defer allocator.free(cps);
    
    var leading_underscores: usize = 0;
    for (cps) |cp| {
        if (cp == constants.CP_UNDERSCORE) {
            leading_underscores += 1;
        } else {
            break;
        }
    }
    
    for (cps[leading_underscores..]) |cp| {
        if (cp == constants.CP_UNDERSCORE) {
            return error_types.ProcessError.CurrableError;
        }
    }
}

fn checkNoHyphenAtSecondAndThird(allocator: std.mem.Allocator, label: TokenizedLabel) !void {
    const cps = try label.iterCps(allocator);
    defer allocator.free(cps);
    
    if (cps.len >= 4 and cps[2] == constants.CP_HYPHEN and cps[3] == constants.CP_HYPHEN) {
        return error_types.ProcessError.CurrableError;
    }
}

fn checkFenced(allocator: std.mem.Allocator, label: TokenizedLabel, specs: *const code_points.CodePointsSpecs) !void {
    const cps = try label.iterCps(allocator);
    defer allocator.free(cps);
    
    if (cps.len == 0) return;
    
    // Check for fenced characters at start and end
    // For now, placeholder implementation
    _ = specs;
    
    // Check for consecutive fenced characters
    for (cps[0..cps.len-1], 0..) |cp, i| {
        const next_cp = cps[i + 1];
        // TODO: implement actual fenced character checking
        _ = cp;
        _ = next_cp;
    }
}

fn checkCmLeadingEmoji(allocator: std.mem.Allocator, label: TokenizedLabel, specs: *const code_points.CodePointsSpecs) !void {
    _ = allocator;
    _ = label;
    _ = specs;
    // TODO: implement combining mark checking
}

fn checkAndGetGroup(allocator: std.mem.Allocator, label: TokenizedLabel, specs: *const code_points.CodePointsSpecs) !*const code_points.ParsedGroup {
    _ = allocator;
    _ = label;
    _ = specs;
    // TODO: implement group determination
    return error_types.ProcessError.Confused;
}

test "validateLabel basic functionality" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test with empty label
    const empty_label = TokenizedLabel{
        .tokens = &[_]tokenizer.Token{},
        .allocator = allocator,
    };
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    const result = validateLabel(allocator, empty_label, &specs);
    try testing.expectError(error_types.ProcessError.DisallowedSequence, result);
}