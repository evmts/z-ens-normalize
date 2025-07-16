const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const constants = @import("constants.zig");
const utils = @import("utils.zig");
const code_points = @import("code_points.zig");
const error_types = @import("error.zig");
const character_mappings = @import("character_mappings.zig");
const static_data_loader = @import("static_data_loader.zig");
const nfc = @import("nfc.zig");
const emoji = @import("emoji.zig");
const log = @import("logger.zig");

pub const OutputToken = struct {
    codepoints: []const CodePoint,
    emoji: ?emoji.EmojiData,  // Optional owned emoji data
    allocator: std.mem.Allocator,
    type: TokenType,
    
    pub fn init(allocator: std.mem.Allocator, codepoints: []const CodePoint, emoji_data: ?*const emoji.EmojiData) !OutputToken {
        // Determine token type based on content
        var token_type: TokenType = if (emoji_data != null) .emoji else .valid;
        
        // Check if this is a stop token (single dot)
        if (codepoints.len == 1 and codepoints[0] == constants.CP_STOP) {
            token_type = .stop;
        }
        
        log.trace("Creating OutputToken: type={s}, codepoints.len={}, emoji={}", .{@tagName(token_type), codepoints.len, emoji_data != null});
        
        // Create owned copy of emoji data if provided
        const owned_emoji = if (emoji_data) |ed| emoji.EmojiData{
            .emoji = try allocator.dupe(CodePoint, ed.emoji),
            .no_fe0f = try allocator.dupe(CodePoint, ed.no_fe0f),
        } else null;
        
        return OutputToken{
            .codepoints = try allocator.dupe(CodePoint, codepoints),
            .emoji = owned_emoji,
            .allocator = allocator,
            .type = token_type,
        };
    }
    
    pub fn deinit(self: OutputToken) void {
        self.allocator.free(self.codepoints);
        if (self.emoji) |emoji_data| {
            emoji_data.deinit(self.allocator);
        }
    }
    
    pub fn isEmoji(self: OutputToken) bool {
        return self.emoji != null;
    }
    
    pub fn isText(self: OutputToken) bool {
        return self.emoji == null;
    }
};

pub const TokenType = enum {
    valid,
    mapped,
    ignored,
    disallowed,
    emoji,
    nfc,
    stop,
    
    pub fn toString(self: TokenType) []const u8 {
        return switch (self) {
            .valid => "valid",
            .mapped => "mapped",
            .ignored => "ignored",
            .disallowed => "disallowed",
            .emoji => "emoji",
            .nfc => "nfc",
            .stop => "stop",
        };
    }
};

pub const Token = struct {
    type: TokenType,
    // Union of possible token data
    data: union(TokenType) {
        valid: struct {
            cps: []const CodePoint,
        },
        mapped: struct {
            cp: CodePoint,
            cps: []const CodePoint,
        },
        ignored: struct {
            cp: CodePoint,
        },
        disallowed: struct {
            cp: CodePoint,
        },
        emoji: struct {
            input: []const CodePoint,
            emoji_data: []const CodePoint,
            cps: []const CodePoint,
        },
        nfc: struct {
            input: []const CodePoint,
            cps: []const CodePoint,
            tokens0: ?[]Token,
            tokens: ?[]Token,
        },
        stop: struct {
            cp: CodePoint,
        },
    },
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, token_type: TokenType) Token {
        return Token{
            .type = token_type,
            .data = switch (token_type) {
                .valid => .{ .valid = .{ .cps = &[_]CodePoint{} } },
                .mapped => .{ .mapped = .{ .cp = 0, .cps = &[_]CodePoint{} } },
                .ignored => .{ .ignored = .{ .cp = 0 } },
                .disallowed => .{ .disallowed = .{ .cp = 0 } },
                .emoji => .{ .emoji = .{ .input = &[_]CodePoint{}, .emoji_data = &[_]CodePoint{}, .cps = &[_]CodePoint{} } },
                .nfc => .{ .nfc = .{ .input = &[_]CodePoint{}, .cps = &[_]CodePoint{}, .tokens0 = null, .tokens = null } },
                .stop => .{ .stop = .{ .cp = constants.CP_STOP } },
            },
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: Token) void {
        switch (self.data) {
            .valid => |data| self.allocator.free(data.cps),
            .mapped => |data| self.allocator.free(data.cps),
            .emoji => |data| {
                self.allocator.free(data.input);
                self.allocator.free(data.emoji_data);
                self.allocator.free(data.cps);
            },
            .nfc => |data| {
                self.allocator.free(data.input);
                self.allocator.free(data.cps);
                if (data.tokens0) |tokens0| {
                    for (tokens0) |token| {
                        token.deinit();
                    }
                    self.allocator.free(tokens0);
                }
                if (data.tokens) |tokens| {
                    for (tokens) |token| {
                        token.deinit();
                    }
                    self.allocator.free(tokens);
                }
            },
            .ignored, .disallowed, .stop => {},
        }
    }
    
    pub fn getCps(self: Token) []const CodePoint {
        return switch (self.data) {
            .valid => |data| data.cps,
            .mapped => |data| data.cps,
            .emoji => |data| data.cps,
            .nfc => |data| data.cps,
            .ignored => |data| &[_]CodePoint{data.cp},
            .disallowed => |data| &[_]CodePoint{data.cp},
            .stop => |data| &[_]CodePoint{data.cp},
        };
    }
    
    pub fn getInputSize(self: Token) usize {
        return switch (self.data) {
            .valid => |data| data.cps.len,
            .nfc => |data| data.input.len,
            .emoji => |data| data.input.len,
            .mapped, .ignored, .disallowed, .stop => 1,
        };
    }
    
    pub fn isText(self: Token) bool {
        return switch (self.type) {
            .valid, .mapped, .nfc => true,
            else => false,
        };
    }
    
    pub fn isEmoji(self: Token) bool {
        return self.type == .emoji;
    }
    
    pub fn isIgnored(self: Token) bool {
        return self.type == .ignored;
    }
    
    pub fn isDisallowed(self: Token) bool {
        return self.type == .disallowed;
    }
    
    pub fn isStop(self: Token) bool {
        return self.type == .stop;
    }
    
    pub fn createValid(allocator: std.mem.Allocator, cps: []const CodePoint) !Token {
        const owned_cps = try allocator.dupe(CodePoint, cps);
        return Token{
            .type = .valid,
            .data = .{ .valid = .{ .cps = owned_cps } },
            .allocator = allocator,
        };
    }
    
    pub fn createMapped(allocator: std.mem.Allocator, cp: CodePoint, cps: []const CodePoint) !Token {
        const owned_cps = try allocator.dupe(CodePoint, cps);
        return Token{
            .type = .mapped,
            .data = .{ .mapped = .{ .cp = cp, .cps = owned_cps } },
            .allocator = allocator,
        };
    }
    
    pub fn createIgnored(allocator: std.mem.Allocator, cp: CodePoint) Token {
        return Token{
            .type = .ignored,
            .data = .{ .ignored = .{ .cp = cp } },
            .allocator = allocator,
        };
    }
    
    pub fn createDisallowed(allocator: std.mem.Allocator, cp: CodePoint) Token {
        return Token{
            .type = .disallowed,
            .data = .{ .disallowed = .{ .cp = cp } },
            .allocator = allocator,
        };
    }
    
    pub fn createStop(allocator: std.mem.Allocator) Token {
        return Token{
            .type = .stop,
            .data = .{ .stop = .{ .cp = constants.CP_STOP } },
            .allocator = allocator,
        };
    }
    
    pub fn createEmoji(
        allocator: std.mem.Allocator,
        input: []const CodePoint,
        emoji_data: []const CodePoint,
        cps: []const CodePoint
    ) !Token {
        const input_copy = try allocator.dupe(CodePoint, input);
        errdefer allocator.free(input_copy);
        
        const emoji_copy = if (emoji_data.ptr == input.ptr and emoji_data.len == input.len) 
            try allocator.dupe(CodePoint, input_copy)
        else 
            try allocator.dupe(CodePoint, emoji_data);
        errdefer allocator.free(emoji_copy);
        
        const cps_copy = if (cps.ptr == input.ptr and cps.len == input.len)
            try allocator.dupe(CodePoint, input_copy)
        else if (cps.ptr == emoji_data.ptr and cps.len == emoji_data.len)
            try allocator.dupe(CodePoint, emoji_copy)
        else
            try allocator.dupe(CodePoint, cps);
        
        return Token{
            .type = .emoji,
            .data = .{ .emoji = .{
                .input = input_copy,
                .emoji_data = emoji_copy,
                .cps = cps_copy,
            }},
            .allocator = allocator,
        };
    }
    
    pub fn createNFC(
        allocator: std.mem.Allocator,
        input: []const CodePoint,
        cps: []const CodePoint,
        tokens0: ?[]Token,
        tokens: ?[]Token,
    ) !Token {
        const owned_tokens0 = if (tokens0) |t| try allocator.dupe(Token, t) else null;
        const owned_tokens = if (tokens) |t| try allocator.dupe(Token, t) else null;
        
        return Token{
            .type = .nfc,
            .data = .{ .nfc = .{
                .input = try allocator.dupe(CodePoint, input),
                .cps = try allocator.dupe(CodePoint, cps),
                .tokens0 = owned_tokens0,
                .tokens = owned_tokens,
            }},
            .allocator = allocator,
        };
    }
};

pub const TokenizedName = struct {
    input: []const u8,
    tokens: []Token,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, input: []const u8) TokenizedName {
        return TokenizedName{
            .input = input,
            .tokens = &[_]Token{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: TokenizedName) void {
        for (self.tokens) |token| {
            token.deinit();
        }
        self.allocator.free(self.tokens);
        self.allocator.free(self.input);
    }
    
    pub fn isEmpty(self: TokenizedName) bool {
        return self.tokens.len == 0;
    }
    
    pub fn fromInput(
        allocator: std.mem.Allocator,
        input: []const u8,
        _: *const code_points.CodePointsSpecs,
        apply_nfc: bool,
    ) !TokenizedName {
        if (input.len == 0) {
            return TokenizedName{
                .input = try allocator.dupe(u8, ""),
                .tokens = &[_]Token{},
                .allocator = allocator,
            };
        }
        
        const tokens = try tokenizeInputWithMappings(allocator, input, apply_nfc);
        
        return TokenizedName{
            .input = try allocator.dupe(u8, input),
            .tokens = tokens,
            .allocator = allocator,
        };
    }
    
    pub fn fromInputWithMappings(
        allocator: std.mem.Allocator,
        input: []const u8,
        mappings: *const character_mappings.CharacterMappings,
        apply_nfc: bool,
    ) !TokenizedName {
        if (input.len == 0) {
            return TokenizedName{
                .input = try allocator.dupe(u8, ""),
                .tokens = &[_]Token{},
                .allocator = allocator,
            };
        }
        
        const tokens = try tokenizeInputWithMappingsImpl(allocator, input, mappings, apply_nfc);
        
        return TokenizedName{
            .input = try allocator.dupe(u8, input),
            .tokens = tokens,
            .allocator = allocator,
        };
    }

    pub fn fromInputWithData(
        allocator: std.mem.Allocator,
        input: []const u8,
        _: *const code_points.CodePointsSpecs,
        mappings: *const character_mappings.CharacterMappings,
        emoji_map: *const emoji.EmojiMap,
        nfc_data: *const nfc.NFCData,
        apply_nfc: bool,
    ) !TokenizedName {
        if (input.len == 0) {
            return TokenizedName{
                .input = try allocator.dupe(u8, ""),
                .tokens = &[_]Token{},
                .allocator = allocator,
            };
        }
        
        const tokens = try tokenizeInputWithMappingsImplWithData(allocator, input, mappings, emoji_map, nfc_data, apply_nfc);
        
        return TokenizedName{
            .input = try allocator.dupe(u8, input),
            .tokens = tokens,
            .allocator = allocator,
        };
    }
};

pub fn streamingTokenize(
    allocator: std.mem.Allocator,
    input: []const u8,
    mappings: *const character_mappings.CharacterMappings,
    emoji_map: *const emoji.EmojiMap,
    nfc_data: *const nfc.NFCData,
    apply_nfc: bool,
) ![]OutputToken {
    log.enterFn("streamingTokenize", "input.len={}, apply_nfc={}", .{input.len, apply_nfc});
    log.unicodeDebug("Input to tokenize", input);
    const timer = log.Timer.start("streamingTokenize");
    defer timer.stop();
    
    var tokens = std.ArrayList(OutputToken).init(allocator);
    errdefer tokens.deinit(); // Only free on error
    
    var text_buffer = std.ArrayList(CodePoint).init(allocator);
    defer text_buffer.deinit();
    
    // Helper function to flush text buffer as token
    const flushTextBuffer = struct {
        fn call(
            alloc: std.mem.Allocator,
            buffer: *std.ArrayList(CodePoint),
            token_list: *std.ArrayList(OutputToken),
            nfc_data_ref: *const nfc.NFCData,
            should_apply_nfc: bool,
        ) !void {
            if (buffer.items.len == 0) return;
            
            log.trace("Flushing text buffer: {} codepoints", .{buffer.items.len});
            var codepoints = buffer.items;
            
            // Apply NFC if requested
            if (should_apply_nfc) {
                log.trace("Applying NFC to {} codepoints", .{buffer.items.len});
                codepoints = nfc.nfc(alloc, buffer.items, nfc_data_ref) catch |err| {
                    log.err("NFC failed with error: {}", .{err});
                    return; // Can't continue if NFC fails
                };
                if (codepoints.len != buffer.items.len) {
                    log.debug("NFC transformed {} codepoints to {} codepoints", .{buffer.items.len, codepoints.len});
                }
            }
            
            const token = try OutputToken.init(alloc, codepoints, null);
            try token_list.append(token);
            log.trace("Added text token with {} codepoints", .{codepoints.len});
            
            // Free NFC result if it was allocated
            if (should_apply_nfc and codepoints.ptr != buffer.items.ptr) {
                alloc.free(codepoints);
            }
            
            buffer.clearRetainingCapacity();
        }
    }.call;
    
    // Process input character by character with emoji priority
    var i: usize = 0;
    while (i < input.len) {
        // Try to match emoji at current position
        if (emoji_map.findEmojiAt(allocator, input, i)) |emoji_match| {
            log.trace("Found emoji at position {}: {} codepoints, {} bytes", .{i, emoji_match.emoji_data.emoji.len, emoji_match.byte_len});
            
            // Flush accumulated text buffer
            try flushTextBuffer(allocator, &text_buffer, &tokens, nfc_data, apply_nfc);
            
            // Add emoji token
            const emoji_token = try OutputToken.init(allocator, emoji_match.emoji_data.no_fe0f, &emoji_match.emoji_data);
            try tokens.append(emoji_token);
            log.debug("Added emoji token with {} codepoints", .{emoji_match.emoji_data.emoji.len});
            
            i += emoji_match.byte_len;
            continue;
        }
        
        // Process regular character
        const char_len = std.unicode.utf8ByteSequenceLength(input[i]) catch 1;
        if (i + char_len > input.len) break;
        
        const cp_bytes = input[i..i + char_len];
        const cp = std.unicode.utf8Decode(cp_bytes) catch {
            // Invalid UTF-8, add replacement character to buffer
            log.warn("Invalid UTF-8 at position {}, using replacement character", .{i});
            try text_buffer.append(0xFFFD);
            i += 1;
            continue;
        };
        
        log.trace("Processing character at position {}: U+{X:0>4}", .{i, cp});
        
        // Classify character and handle accordingly
        if (cp == constants.CP_STOP) {
            log.debug("Found STOP character (.) at position {}", .{i});
            // Flush text buffer and add stop character as separate token
            try flushTextBuffer(allocator, &text_buffer, &tokens, nfc_data, apply_nfc);
            const stop_token = try OutputToken.init(allocator, &[_]CodePoint{cp}, null);
            try tokens.append(stop_token);
        } else if (mappings.isIgnored(cp)) {
            log.trace("Character U+{X:0>4} is ignored", .{cp});
            // Ignored characters are not added to buffer
        } else if (mappings.getMapped(cp)) |mapped| {
            log.trace("Character U+{X:0>4} maps to {} codepoints", .{cp, mapped.len});
            // Add mapped codepoints to buffer
            try text_buffer.appendSlice(mapped);
        } else if (mappings.isValid(cp)) {
            log.trace("Character U+{X:0>4} is valid", .{cp});
            // Add valid character to buffer
            try text_buffer.append(cp);
        } else {
            log.warn("Character U+{X:0>4} is disallowed but adding to buffer for validation", .{cp});
            // Disallowed character - for now, add to buffer (validation will catch it)
            try text_buffer.append(cp);
        }
        
        i += char_len;
    }
    
    // Flush any remaining text in buffer
    log.trace("Flushing final text buffer", .{});
    try flushTextBuffer(allocator, &text_buffer, &tokens, nfc_data, apply_nfc);
    
    const result = try tokens.toOwnedSlice();
    log.exitFn("streamingTokenize", "tokens.len={}", .{result.len});
    return result;
}

pub const StreamTokenizedName = struct {
    input: []const u8,
    tokens: []OutputToken,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, input: []const u8) StreamTokenizedName {
        return StreamTokenizedName{
            .input = input,
            .tokens = &[_]OutputToken{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: StreamTokenizedName) void {
        for (self.tokens) |token| {
            token.deinit();
        }
        self.allocator.free(self.tokens);
        self.allocator.free(self.input);
    }
    
    pub fn isEmpty(self: StreamTokenizedName) bool {
        return self.tokens.len == 0;
    }
    
    pub fn fromInputWithData(
        allocator: std.mem.Allocator,
        input: []const u8,
        _: *const code_points.CodePointsSpecs,
        mappings: *const character_mappings.CharacterMappings,
        emoji_map: *const emoji.EmojiMap,
        nfc_data: *const nfc.NFCData,
        apply_nfc: bool,
    ) !StreamTokenizedName {
        log.enterFn("StreamTokenizedName.fromInputWithData", "input.len={}, apply_nfc={}", .{input.len, apply_nfc});
        log.unicodeDebug("Creating StreamTokenizedName for input", input);
        
        if (input.len == 0) {
            log.debug("Empty input, returning empty token list", .{});
            return StreamTokenizedName{
                .input = try allocator.dupe(u8, ""),
                .tokens = &[_]OutputToken{},
                .allocator = allocator,
            };
        }
        
        const tokens = try streamingTokenize(allocator, input, mappings, emoji_map, nfc_data, apply_nfc);
        log.info("Tokenization complete: {} tokens generated", .{tokens.len});
        
        for (tokens, 0..) |token, i| {
            log.debug("Token[{}]: type={s}, codepoints.len={}, emoji={}", .{i, @tagName(token.type), token.codepoints.len, token.emoji != null});
        }
        
        const result = StreamTokenizedName{
            .input = try allocator.dupe(u8, input),
            .tokens = tokens,
            .allocator = allocator,
        };
        
        log.exitFn("StreamTokenizedName.fromInputWithData", "tokens.len={}", .{result.tokens.len});
        return result;
    }
};


fn tokenizeInputWithMappings(
    allocator: std.mem.Allocator,
    input: []const u8,
    apply_nfc: bool,
) ![]Token {
    log.enterFn("tokenizeInputWithMappings", "input.len={}, apply_nfc={}", .{input.len, apply_nfc});
    
    // Load complete character mappings from spec.zon
    var mappings = static_data_loader.loadCharacterMappings(allocator) catch |err| blk: {
        // Fall back to basic mappings if spec.zon loading fails
        log.warn("Failed to load spec.zon: {}, using basic mappings", .{err});
        break :blk try static_data_loader.loadCharacterMappings(allocator);
    };
    defer mappings.deinit();
    
    return tokenizeInputWithMappingsImpl(allocator, input, &mappings, apply_nfc);
}

fn tokenizeInputWithMappingsImpl(
    allocator: std.mem.Allocator,
    input: []const u8,
    mappings: *const character_mappings.CharacterMappings,
    apply_nfc: bool,
) ![]Token {
    log.enterFn("tokenizeInputWithMappingsImpl", "input.len={}, apply_nfc={}", .{input.len, apply_nfc});
    log.unicodeDebug("Tokenizing input", input);
    
    var tokens = std.ArrayList(Token).init(allocator);
    errdefer tokens.deinit(); // Only free on error
    
    // Load emoji map
    var emoji_map = static_data_loader.loadEmoji(allocator) catch |err| {
        // If emoji loading fails, fall back to character-by-character processing
        std.debug.print("Warning: Failed to load emoji map: {}\n", .{err});
        return tokenizeWithoutEmoji(allocator, input, mappings, apply_nfc);
    };
    defer emoji_map.deinit();
    
    // Process input looking for emojis first
    var i: usize = 0;
    while (i < input.len) {
        // Try to match emoji at current position
        if (emoji_map.findEmojiAt(allocator, input, i)) |match| {
            defer allocator.free(match.cps_input); // Free the owned copy
            // Create emoji token
            try tokens.append(try Token.createEmoji(
                allocator,
                match.cps_input,
                match.emoji_data.emoji,
                match.emoji_data.no_fe0f
            ));
            i += match.byte_len;
        } else {
            // Process single character
            const char_len = std.unicode.utf8ByteSequenceLength(input[i]) catch 1;
            if (i + char_len > input.len) break;
            
            const cp = std.unicode.utf8Decode(input[i..i + char_len]) catch {
                try tokens.append(Token.createDisallowed(allocator, 0xFFFD)); // replacement character
                i += 1;
                continue;
            };
            
            if (cp == constants.CP_STOP) {
                try tokens.append(Token.createStop(allocator));
            } else if (mappings.getMapped(cp)) |mapped| {
                try tokens.append(try Token.createMapped(allocator, cp, mapped));
            } else if (mappings.isValid(cp)) {
                try tokens.append(try Token.createValid(allocator, &[_]CodePoint{cp}));
            } else if (mappings.isIgnored(cp)) {
                try tokens.append(Token.createIgnored(allocator, cp));
            } else {
                try tokens.append(Token.createDisallowed(allocator, cp));
            }
            
            i += char_len;
        }
    }
    
    // Apply NFC transformation if requested
    if (apply_nfc) {
        var nfc_data = try static_data_loader.loadNFC(allocator);
        defer nfc_data.deinit();
        try applyNFCTransform(allocator, &tokens, &nfc_data);
    }
    
    // Collapse consecutive valid tokens
    try collapseValidTokens(allocator, &tokens);
    
    return tokens.toOwnedSlice();
}

fn tokenizeInputWithMappingsImplWithData(
    allocator: std.mem.Allocator,
    input: []const u8,
    mappings: *const character_mappings.CharacterMappings,
    emoji_map: *const emoji.EmojiMap,
    nfc_data: *const nfc.NFCData,
    apply_nfc: bool,
) ![]Token {
    log.enterFn("tokenizeInputWithMappingsImplWithData", "input.len={}, apply_nfc={}", .{input.len, apply_nfc});
    log.unicodeDebug("Tokenizing with full data", input);
    const timer = log.Timer.start("tokenizeInputWithMappingsImplWithData");
    defer timer.stop();
    
    var tokens = std.ArrayList(Token).init(allocator);
    errdefer tokens.deinit(); // Only free on error
    
    // Process input looking for emojis first
    var i: usize = 0;
    while (i < input.len) {
        // Try to match emoji at current position
        if (emoji_map.findEmojiAt(allocator, input, i)) |emoji_match| {
            // Convert input to codepoints
            const input_cps = utils.str2cps(allocator, emoji_match.input) catch {
                // If conversion fails, treat as regular characters
                const char_len = std.unicode.utf8ByteSequenceLength(input[i]) catch 1;
                if (i + char_len > input.len) break;
                
                const cp_bytes = input[i..i + char_len];
                const cp = std.unicode.utf8Decode(cp_bytes) catch 0xFFFD;
                try tokens.append(Token.createDisallowed(allocator, cp));
                i += 1;
                continue;
            };
            defer allocator.free(input_cps);
            
            try tokens.append(try Token.createEmoji(
                allocator,
                emoji_match.cps_input,
                emoji_match.emoji_data.emoji,
                emoji_match.emoji_data.no_fe0f
            ));
            i += emoji_match.byte_len;
            continue;
        }
        
        // Not an emoji, process as regular character
        const char_len = std.unicode.utf8ByteSequenceLength(input[i]) catch 1;
        if (i + char_len > input.len) break;
        
        const cp_bytes = input[i..i + char_len];
        const cp = std.unicode.utf8Decode(cp_bytes) catch {
            // Invalid UTF-8, treat as disallowed
            try tokens.append(Token.createDisallowed(allocator, 0xFFFD));
            i += 1;
            continue;
        };
        
        // Check character classification
        if (cp == constants.CP_STOP) {
            try tokens.append(Token.createStop(allocator));
        } else if (mappings.isIgnored(cp)) {
            try tokens.append(Token.createIgnored(allocator, cp));
        } else if (mappings.getMapped(cp)) |mapped| {
            try tokens.append(try Token.createMapped(allocator, cp, mapped));
        } else if (mappings.isValid(cp)) {
            try tokens.append(try Token.createValid(allocator, &[_]CodePoint{cp}));
        } else {
            try tokens.append(Token.createDisallowed(allocator, cp));
        }
        
        i += char_len;
    }
    
    // Apply NFC transformation if requested
    if (apply_nfc) {
        try applyNFCTransform(allocator, &tokens, nfc_data);
    }
    
    // Collapse consecutive valid tokens
    try collapseValidTokens(allocator, &tokens);
    
    return tokens.toOwnedSlice();
}

fn collapseValidTokens(allocator: std.mem.Allocator, tokens: *std.ArrayList(Token)) !void {
    var i: usize = 0;
    while (i < tokens.items.len) {
        if (tokens.items[i].type == .valid) {
            var j = i + 1;
            var combined_cps = std.ArrayList(CodePoint).init(allocator);
            defer combined_cps.deinit();
            
            // Add first token's cps
            try combined_cps.appendSlice(tokens.items[i].getCps());
            
            // Collect consecutive valid tokens
            while (j < tokens.items.len and tokens.items[j].type == .valid) {
                try combined_cps.appendSlice(tokens.items[j].getCps());
                j += 1;
            }
            
            if (j > i + 1) {
                // We have multiple valid tokens to collapse
                
                // Clean up the old tokens
                for (tokens.items[i..j]) |token| {
                    token.deinit();
                }
                
                // Create new collapsed token
                const new_token = try Token.createValid(allocator, combined_cps.items);
                
                // Replace the range with the new token
                tokens.replaceRange(i, j - i, &[_]Token{new_token}) catch |err| {
                    new_token.deinit();
                    return err;
                };
            }
        }
        i += 1;
    }
}

test "tokenization basic functionality" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test simple ASCII
    const result = try TokenizedName.fromInput(allocator, "hello", &specs, false);
    try testing.expect(result.tokens.len > 0);
    try testing.expect(result.tokens[0].type == .valid);
    
    // Test with stop character
    const result2 = try TokenizedName.fromInput(allocator, "hello.eth", &specs, false);
    var found_stop = false;
    for (result2.tokens) |token| {
        if (token.type == .stop) {
            found_stop = true;
            break;
        }
    }
    try testing.expect(found_stop);
}

test "token creation and cleanup" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test valid token
    const cps = [_]CodePoint{ 'h', 'e', 'l', 'l', 'o' };
    const token = try Token.createValid(allocator, &cps);
    try testing.expectEqual(TokenType.valid, token.type);
    try testing.expectEqualSlices(CodePoint, &cps, token.getCps());
    
    // Test stop token
    const stop_token = Token.createStop(allocator);
    try testing.expectEqual(TokenType.stop, stop_token.type);
    try testing.expectEqual(constants.CP_STOP, stop_token.data.stop.cp);
    
    // Test ignored token (using soft hyphen as example)
    const ignored_token = Token.createIgnored(allocator, 0x00AD);
    try testing.expectEqual(TokenType.ignored, ignored_token.type);
    try testing.expectEqual(@as(CodePoint, 0x00AD), ignored_token.data.ignored.cp);
}

test "token input size calculation" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test valid token input size
    const cps = [_]CodePoint{ 'h', 'e', 'l', 'l', 'o' };
    const token = try Token.createValid(allocator, &cps);
    try testing.expectEqual(@as(usize, 5), token.getInputSize());
    
    // Test stop token input size
    const stop_token = Token.createStop(allocator);
    try testing.expectEqual(@as(usize, 1), stop_token.getInputSize());
}

test "token type checking" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const cps = [_]CodePoint{'h'};
    const text_token = try Token.createValid(allocator, &cps);
    try testing.expect(text_token.isText());
    try testing.expect(!text_token.isEmoji());
    
    const stop_token = Token.createStop(allocator);
    try testing.expect(!stop_token.isText());
    try testing.expect(!stop_token.isEmoji());
}

test "empty input handling" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    const result = try TokenizedName.fromInput(allocator, "", &specs, false);
    try testing.expect(result.isEmpty());
    try testing.expectEqual(@as(usize, 0), result.tokens.len);
}

test "emoji tokenization" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test simple emoji
    const input = "hello👍world";
    const result = try TokenizedName.fromInput(allocator, input, &specs, false);
    defer result.deinit();
    
    // Should have: valid("hello"), emoji(👍), valid("world")
    try testing.expect(result.tokens.len >= 3);
    
    var found_emoji = false;
    for (result.tokens) |token| {
        if (token.type == .emoji) {
            found_emoji = true;
            break;
        }
    }
    
    try testing.expect(found_emoji);
}

test "whitespace tokenization" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test various whitespace characters
    const whitespace_tests = [_]struct { input: []const u8, name: []const u8 }{
        .{ .input = " ", .name = "space" },
        .{ .input = "\t", .name = "tab" },
        .{ .input = "\n", .name = "newline" },
        .{ .input = "\u{00A0}", .name = "non-breaking space" },
        .{ .input = "\u{2000}", .name = "en quad" },
    };
    
    for (whitespace_tests) |test_case| {
        const result = try TokenizedName.fromInput(allocator, test_case.input, &specs, false);
        defer result.deinit();
        
        std.debug.print("\n{s}: tokens={}, ", .{ test_case.name, result.tokens.len });
        if (result.tokens.len > 0) {
            std.debug.print("type={s}", .{@tagName(result.tokens[0].type)});
            if (result.tokens[0].type == .disallowed) {
                std.debug.print(" cp=0x{x}", .{result.tokens[0].data.disallowed.cp});
            }
        }
    }
    std.debug.print("\n", .{});
}


test "token collapse functionality" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    const result = try TokenizedName.fromInput(allocator, "hello", &specs, false);
    
    // Should collapse consecutive valid tokens into one
    try testing.expect(result.tokens.len > 0);
    
    // Check that we have valid tokens
    var has_valid = false;
    for (result.tokens) |token| {
        if (token.type == .valid) {
            has_valid = true;
            break;
        }
    }
    try testing.expect(has_valid);
}

fn tokenizeWithoutEmoji(
    allocator: std.mem.Allocator,
    input: []const u8,
    mappings: *const character_mappings.CharacterMappings,
    apply_nfc: bool,
) ![]Token {
    log.enterFn("tokenizeWithoutEmoji", "input.len={}, apply_nfc={}", .{input.len, apply_nfc});
    
    var tokens = std.ArrayList(Token).init(allocator);
    errdefer tokens.deinit(); // Only free on error
    
    // Convert input to code points
    const cps = try utils.str2cps(allocator, input);
    log.debug("Converted input to {} codepoints", .{cps.len});
    defer allocator.free(cps);
    
    for (cps) |cp| {
        if (cp == constants.CP_STOP) {
            try tokens.append(Token.createStop(allocator));
        } else if (mappings.getMapped(cp)) |mapped| {
            try tokens.append(try Token.createMapped(allocator, cp, mapped));
        } else if (mappings.isValid(cp)) {
            try tokens.append(try Token.createValid(allocator, &[_]CodePoint{cp}));
        } else if (mappings.isIgnored(cp)) {
            try tokens.append(Token.createIgnored(allocator, cp));
        } else {
            try tokens.append(Token.createDisallowed(allocator, cp));
        }
    }
    
    // Apply NFC transformation if requested
    if (apply_nfc) {
        var nfc_data = try static_data_loader.loadNFC(allocator);
        defer nfc_data.deinit();
        try applyNFCTransform(allocator, &tokens, &nfc_data);
    }
    
    // Collapse consecutive valid tokens
    try collapseValidTokens(allocator, &tokens);
    
    return tokens.toOwnedSlice();
}

fn applyNFCTransform(allocator: std.mem.Allocator, tokens: *std.ArrayList(Token), nfc_data: *const nfc.NFCData) !void {
    var i: usize = 0;
    while (i < tokens.items.len) {
        const token = &tokens.items[i];
        
        // Check if this token starts a sequence that needs NFC
        switch (token.data) {
            .valid, .mapped => {
                const start_cps = token.getCps();
                
                // Check if any codepoint needs NFC checking
                var needs_check = false;
                for (start_cps) |cp| {
                    if (nfc_data.requiresNFCCheck(cp)) {
                        needs_check = true;
                        break;
                    }
                }
                
                if (needs_check) {
                    // Find the end of the sequence that needs NFC
                    var end = i + 1;
                    while (end < tokens.items.len) : (end += 1) {
                        switch (tokens.items[end].data) {
                            .valid, .mapped => {
                                // Continue including valid/mapped tokens
                            },
                            .ignored => {
                                // Skip ignored tokens but continue
                            },
                            else => break,
                        }
                    }
                    
                    // Collect all codepoints in the range (excluding ignored)
                    var all_cps = std.ArrayList(CodePoint).init(allocator);
                    defer all_cps.deinit();
                    
                    var j = i;
                    while (j < end) : (j += 1) {
                        switch (tokens.items[j].data) {
                            .valid, .mapped => {
                                try all_cps.appendSlice(tokens.items[j].getCps());
                            },
                            else => {},
                        }
                    }
                    
                    // Apply NFC
                    const normalized = try nfc.nfc(allocator, all_cps.items, nfc_data);
                    defer allocator.free(normalized);
                    
                    // Check if normalization changed anything
                    if (!nfc.compareCodePoints(all_cps.items, normalized)) {
                        // Collect the original tokens for tokens0
                        var tokens0 = try allocator.alloc(Token, end - i);
                        for (tokens.items[i..end], 0..) |orig_token, idx| {
                            // Create a copy of the token without transferring ownership
                            tokens0[idx] = switch (orig_token.data) {
                                .valid => |data| try Token.createValid(allocator, data.cps),
                                .mapped => |data| try Token.createMapped(allocator, data.cp, data.cps),
                                .ignored => |data| Token.createIgnored(allocator, data.cp),
                                else => unreachable,
                            };
                        }
                        
                        // Create NFC token with tokens0
                        const nfc_token = try Token.createNFC(
                            allocator,
                            all_cps.items,
                            normalized,
                            tokens0,
                            null  // tokens field would be populated by re-tokenizing normalized string
                        );
                        
                        // Clean up old tokens
                        for (tokens.items[i..end]) |old_token| {
                            old_token.deinit();
                        }
                        
                        // Replace with NFC token
                        tokens.replaceRange(i, end - i, &[_]Token{nfc_token}) catch |err| {
                            nfc_token.deinit();
                            return err;
                        };
                        
                        // Don't increment i, we replaced the current position
                        continue;
                    }
                }
            },
            else => {},
        }
        
        i += 1;
    }
}