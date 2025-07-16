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
const log = @import("logger.zig");
const static_data_loader = @import("static_data_loader.zig");
const nfc = @import("nfc.zig");

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
        // Properly deinit each token before freeing the array
        for (self.tokens) |token| {
            token.deinit();
        }
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
        errdefer result.deinit(); // Only free on error
        
        for (self.tokens) |token| {
            const cps = token.getCps();
            try result.appendSlice(cps);
        }
        
        return result.toOwnedSlice();
    }
    
    pub fn getCpsOfNotIgnoredText(self: TokenizedLabel, allocator: std.mem.Allocator) ![]CodePoint {
        var result = std.ArrayList(CodePoint).init(allocator);
        errdefer result.deinit(); // Only free on error
        
        for (self.tokens) |token| {
            if (!token.isIgnored() and token.isText()) {
                const cps = token.getCps();
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
    log.enterFn("validateName", "tokens.len={}", .{name.tokens.len});
    
    if (name.tokens.len == 0) {
        log.debug("Empty name, returning empty label array", .{});
        return try allocator.alloc(ValidatedLabel, 0);
    }
    
    // For now, create a simple implementation that treats the entire name as one label
    // The actual implementation would need to split on stop tokens
    var labels = std.ArrayList(ValidatedLabel).init(allocator);
    errdefer labels.deinit(); // Only free on error
    
    const label = TokenizedLabel{
        .tokens = name.tokens,
        .allocator = allocator,
    };
    
    log.debug("Validating label with {} tokens", .{label.tokens.len});
    const validated = try validateLabel(allocator, label, specs);
    try labels.append(validated);
    
    const result = try labels.toOwnedSlice();
    log.exitFn("validateName", "labels.len={}", .{result.len});
    return result;
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
    errdefer labels.deinit(); // Only free on error
    
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
    log.enterFn("validateNameWithStreamData", "tokens.len={}", .{name.tokens.len});
    const timer = log.Timer.start("validateNameWithStreamData");
    defer timer.stop();
    
    _ = confusables_data;
    
    if (name.tokens.len == 0) {
        log.debug("Empty name, returning empty label array", .{});
        return try allocator.alloc(ValidatedLabel, 0);
    }
    
    log.debug("Validating stream name with {} tokens", .{name.tokens.len});
    
    // Split tokens into labels based on STOP tokens (dots)
    var labels = std.ArrayList(ValidatedLabel).init(allocator);
    errdefer labels.deinit(); // Only free on error
    
    var current_label_tokens = std.ArrayList(tokenizer.Token).init(allocator);
    defer {
        // Clean up any remaining tokens
        for (current_label_tokens.items) |token| {
            token.deinit();
        }
        current_label_tokens.deinit();
    }
    
    // Process tokens and split on STOP
    for (name.tokens, 0..) |output_token, token_idx| {
        // Early check for emoji + combining mark pattern (should fail)
        if (token_idx > 0 and 
            name.tokens[token_idx - 1].isEmoji() and 
            output_token.type == .valid and
            output_token.codepoints.len > 0 and
            isCombiningMark(output_token.codepoints[0])) {
            log.err("Combining mark after emoji found: U+{X:0>4}", .{output_token.codepoints[0]});
            return error_types.ProcessError.DisallowedSequence;
        }
        
        // Check if this is a STOP token
        if (output_token.type == .stop) {
            log.debug("Found STOP token at position {}, validating current label with {} tokens", .{token_idx, current_label_tokens.items.len});
            
            // Check for leading dot (first token is stop)
            if (token_idx == 0) {
                log.err("Leading dot found", .{});
                return error_types.ProcessError.DisallowedSequence;
            }
            
            // Validate the current label if it has tokens
            if (current_label_tokens.items.len > 0) {
                const label = TokenizedLabel{
                    .tokens = current_label_tokens.items,
                    .allocator = allocator,
                };
                
                const validated = try validateLabelWithGroups(allocator, label, specs, script_groups_data);
                try labels.append(validated);
                
                // Clear the current label tokens for the next label (tokens now owned by ValidatedLabel)
                current_label_tokens.clearRetainingCapacity();
            } else {
                // Empty label - this is an error
                log.err("Empty label found", .{});
                return error_types.ProcessError.DisallowedSequence;
            }
        } else {
            // Convert OutputToken to legacy Token format
            if (output_token.isEmoji()) {
                // Create emoji token - check emoji data is valid first
                if (output_token.emoji) |emoji_data| {
                    log.debug("Creating emoji token with input.len={}, emoji.len={}, cps.len={}", .{
                        output_token.codepoints.len, emoji_data.emoji.len, output_token.codepoints.len
                    });
                    const emoji_token = try tokenizer.Token.createEmoji(
                        allocator,
                        output_token.codepoints,
                        emoji_data.emoji,
                        emoji_data.emoji // Use the canonical emoji form as the cps
                    );
                    try current_label_tokens.append(emoji_token);
                } else {
                    // Should not happen - emoji token without emoji data
                    log.err("Emoji token without emoji data found", .{});
                    return error_types.ProcessError.DisallowedSequence;
                }
            } else {
                // Create appropriate token based on type
                const token = switch (output_token.type) {
                    .valid => try tokenizer.Token.createValid(allocator, output_token.codepoints),
                    .mapped => blk: {
                        // For mapped tokens, we need the original codepoint
                        // Since we don't have it in OutputToken, use the first codepoint
                        const cp = if (output_token.codepoints.len > 0) output_token.codepoints[0] else 0;
                        break :blk try tokenizer.Token.createMapped(allocator, cp, output_token.codepoints);
                    },
                    .ignored => tokenizer.Token.createIgnored(allocator, if (output_token.codepoints.len > 0) output_token.codepoints[0] else 0),
                    .disallowed => tokenizer.Token.createDisallowed(allocator, if (output_token.codepoints.len > 0) output_token.codepoints[0] else 0),
                    .nfc => try tokenizer.Token.createNFC(allocator, output_token.codepoints, output_token.codepoints, null, null),
                    else => unreachable, // stop already handled above
                };
                try current_label_tokens.append(token);
            }
        }
    }
    
    // Don't forget the last label (no trailing dot)
    if (current_label_tokens.items.len > 0) {
        log.debug("Validating final label with {} tokens", .{current_label_tokens.items.len});
        
        const label = TokenizedLabel{
            .tokens = current_label_tokens.items,
            .allocator = allocator,
        };
        
        const validated = try validateLabel(allocator, label, specs);
        try labels.append(validated);
        
        // Clear tokens since they're now owned by the validated label
        current_label_tokens.clearRetainingCapacity();
    } else if (name.tokens.len > 0 and name.tokens[name.tokens.len - 1].type == .stop) {
        // Trailing dot - this is an error
        log.err("Trailing dot found", .{});
        return error_types.ProcessError.DisallowedSequence;
    }
    
    log.info("Validated {} labels", .{labels.items.len});
    return labels.toOwnedSlice();
}

pub fn validateLabel(
    allocator: std.mem.Allocator,
    label: TokenizedLabel,
    specs: *const code_points.CodePointsSpecs,
) !ValidatedLabel {
    // For now, create temporary script groups for NSM checking
    // In real implementation, this should be passed from caller
    var script_groups_data = try static_data_loader.loadScriptGroups(allocator);
    defer script_groups_data.deinit();
    
    return validateLabelWithGroups(allocator, label, specs, &script_groups_data);
}

fn validateLabelWithGroups(
    allocator: std.mem.Allocator,
    label: TokenizedLabel,
    specs: *const code_points.CodePointsSpecs,
    script_groups_data: *const script_groups.ScriptGroups,
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
    
    // Check NSM (Non-Spacing Mark) rules
    try checkNonSpacingMarks(allocator, label, specs, script_groups_data);
    
    // Determine label type based on content
    const label_type = try determineLabelType(allocator, label);
    return ValidatedLabel.init(allocator, label.tokens, label_type);
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
    
    // This implements the Go checkLeadingUnderscore logic:
    // Underscores are only allowed at the beginning of a label
    var allowed = true;
    for (cps) |cp| {
        if (allowed) {
            if (cp != constants.CP_UNDERSCORE) {
                allowed = false;
            }
        } else {
            if (cp == constants.CP_UNDERSCORE) {
                return error_types.ProcessError.DisallowedSequence;
            }
        }
    }
}

fn checkNoHyphenAtSecondAndThird(allocator: std.mem.Allocator, label: TokenizedLabel) !void {
    const cps = try label.iterCps(allocator);
    defer allocator.free(cps);
    
    // This implements the Go checkLabelExtension logic:
    // Labels cannot have hyphens at positions 2 and 3 (xn-- is invalid)
    if (cps.len >= 4 and cps[2] == constants.CP_HYPHEN and cps[3] == constants.CP_HYPHEN) {
        return error_types.ProcessError.DisallowedSequence;
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
    _ = specs;
    
    // Check for leading combining marks and combining marks after emoji
    // This implements the Java checkCombiningMarks logic
    
    for (label.tokens, 0..) |token, i| {
        if (token.isEmoji()) continue;
        
        const cps = token.getCps();
        if (cps.len == 0) continue;
        
        const first_cp = cps[0];
        if (isCombiningMark(first_cp)) {
            if (i == 0) {
                // Leading combining mark
                log.err("Leading combining mark found: U+{X:0>4}", .{first_cp});
                return error_types.ProcessError.DisallowedSequence;
            } else {
                // Check if previous token was emoji
                const prev_token = label.tokens[i - 1];
                if (prev_token.isEmoji()) {
                    log.err("Combining mark after emoji found: U+{X:0>4}", .{first_cp});
                    return error_types.ProcessError.DisallowedSequence;
                }
            }
        }
    }
}

/// Basic check for combining marks using Unicode categories
fn isCombiningMark(cp: CodePoint) bool {
    // Common combining marks (overlaps with NSM but focuses on combining behavior)
    // This is a simplified check - full implementation would use Unicode data
    return (cp >= 0x0300 and cp <= 0x036F) or // Combining Diacritical Marks
           (cp >= 0x1AB0 and cp <= 0x1AFF) or // Combining Diacritical Marks Extended
           (cp >= 0x1DC0 and cp <= 0x1DFF) or // Combining Diacritical Marks Supplement
           (cp >= 0x20D0 and cp <= 0x20FF) or // Combining Diacritical Marks for Symbols
           (cp >= 0xFE20 and cp <= 0xFE2F);   // Combining Half Marks
}

fn checkNonSpacingMarks(allocator: std.mem.Allocator, label: TokenizedLabel, specs: *const code_points.CodePointsSpecs, script_groups_data: *const script_groups.ScriptGroups) !void {
    _ = specs; // Not used in this function
    // Get all codepoints and apply NFD decomposition
    const cps = try label.iterCps(allocator);
    defer allocator.free(cps);
    
    // We need NFC data for decomposition
    var nfc_data = try static_data_loader.loadNFC(allocator);
    defer nfc_data.deinit();
    
    // Apply NFD decomposition
    const nfd_cps = try nfc.decompose(allocator, cps, &nfc_data);
    defer allocator.free(nfd_cps);
    
    // Maximum allowed consecutive non-spacing marks (from C# reference)
    const MAX_NON_SPACING_MARKS = 4;
    
    // Iterate through decomposed codepoints
    var i: usize = 1; // Start from 1 as per C# implementation
    while (i < nfd_cps.len) : (i += 1) {
        // Check if this is a non-spacing mark
        if (script_groups_data.isNSM(nfd_cps[i])) {
            const start_i = i;
            var j = i + 1;
            
            // Find consecutive NSMs
            while (j < nfd_cps.len and script_groups_data.isNSM(nfd_cps[j])) : (j += 1) {
                // Check for duplicate NSMs
                var k = start_i;
                while (k < j) : (k += 1) {
                    if (nfd_cps[k] == nfd_cps[j]) {
                        log.err("Duplicate non-spacing mark found: U+{X:0>4}", .{nfd_cps[j]});
                        return error_types.ProcessError.DisallowedSequence;
                    }
                }
            }
            
            // Check if we have too many consecutive NSMs
            const nsm_count = j - start_i;
            if (nsm_count > MAX_NON_SPACING_MARKS) {
                log.err("Excessive non-spacing marks: {} (max allowed: {})", .{nsm_count, MAX_NON_SPACING_MARKS});
                return error_types.ProcessError.DisallowedSequence;
            }
            
            // Update i to continue after the NSM sequence
            i = j - 1; // -1 because loop will increment
        }
    }
}

/// Determine the script type of a label
fn determineLabelType(allocator: std.mem.Allocator, label: TokenizedLabel) !LabelType {
    // Check easy cases first
    if (label.isFullyEmoji()) {
        return LabelType.emoji;
    }
    
    if (label.isFullyAscii()) {
        return LabelType.ascii;
    }
    
    // For non-ASCII labels, check if they're purely Greek
    const non_ignored_cps = try label.getCpsOfNotIgnoredText(allocator);
    defer allocator.free(non_ignored_cps);
    
    if (non_ignored_cps.len == 0) {
        return LabelType.ascii; // Default for empty
    }
    
    // Check if all codepoints are Greek
    var all_greek = true;
    for (non_ignored_cps) |cp| {
        if (!isGreekCodepoint(cp)) {
            all_greek = false;
            break;
        }
    }
    
    if (all_greek) {
        return LabelType.greek;
    }
    
    // TODO: Add detection for other scripts (Cyrillic, Arabic, etc.)
    return LabelType{ .other = "Unicode" };
}

/// Check if a codepoint is Greek script
fn isGreekCodepoint(cp: CodePoint) bool {
    // Greek and Coptic: U+0370 - U+03FF
    // Greek Extended: U+1F00 - U+1FFF
    return (cp >= 0x0370 and cp <= 0x03FF) or (cp >= 0x1F00 and cp <= 0x1FFF);
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