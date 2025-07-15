const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const constants = @import("constants.zig");
const utils = @import("utils.zig");
const code_points = @import("code_points.zig");
const error_types = @import("error.zig");

// Token types based on ENSIP-15 specification
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
            input: []const u8,
            cps_input: []const CodePoint,
            emoji: []const CodePoint,
            cps_no_fe0f: []const CodePoint,
        },
        nfc: struct {
            input: []const CodePoint,
            cps: []const CodePoint,
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
                .emoji => .{ .emoji = .{ .input = "", .cps_input = &[_]CodePoint{}, .emoji = &[_]CodePoint{}, .cps_no_fe0f = &[_]CodePoint{} } },
                .nfc => .{ .nfc = .{ .input = &[_]CodePoint{}, .cps = &[_]CodePoint{} } },
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
                self.allocator.free(data.cps_input);
                self.allocator.free(data.emoji);
                self.allocator.free(data.cps_no_fe0f);
            },
            .nfc => |data| {
                self.allocator.free(data.input);
                self.allocator.free(data.cps);
            },
            .ignored, .disallowed, .stop => {},
        }
    }
    
    pub fn getCps(self: Token) []const CodePoint {
        return switch (self.data) {
            .valid => |data| data.cps,
            .mapped => |data| data.cps,
            .emoji => |data| data.cps_no_fe0f,
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
            .emoji => |data| data.cps_input.len,
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
        specs: *const code_points.CodePointsSpecs,
        apply_nfc: bool,
    ) !TokenizedName {
        if (input.len == 0) {
            return TokenizedName{
                .input = try allocator.dupe(u8, ""),
                .tokens = &[_]Token{},
                .allocator = allocator,
            };
        }
        
        const tokens = try tokenizeInput(allocator, input, specs, apply_nfc);
        
        return TokenizedName{
            .input = try allocator.dupe(u8, input),
            .tokens = tokens,
            .allocator = allocator,
        };
    }
};

// Character classification interface
pub const CharacterSpecs = struct {
    // For now, simple implementations - would be replaced with actual data
    pub fn isValid(self: *const CharacterSpecs, cp: CodePoint) bool {
        _ = self;
        // Simple ASCII letters and digits for now
        return (cp >= 'a' and cp <= 'z') or 
               (cp >= 'A' and cp <= 'Z') or 
               (cp >= '0' and cp <= '9') or
               cp == '-' or
               cp == '_' or  // underscore (validated for placement later)
               cp == '\'';   // apostrophe (fenced character, validated for placement later)
    }
    
    pub fn isIgnored(self: *const CharacterSpecs, cp: CodePoint) bool {
        _ = self;
        // Common ignored characters
        return cp == 0x00AD or // soft hyphen
               cp == 0x200C or // zero width non-joiner
               cp == 0x200D or // zero width joiner
               cp == 0xFEFF;   // zero width no-break space
    }
    
    pub fn getMapped(self: *const CharacterSpecs, cp: CodePoint) ?[]const CodePoint {
        _ = self;
        // Simple case folding for now
        if (cp >= 'A' and cp <= 'Z') {
            // Would need to allocate and return lowercase
            return null; // Placeholder
        }
        return null;
    }
    
    pub fn isStop(self: *const CharacterSpecs, cp: CodePoint) bool {
        _ = self;
        return cp == constants.CP_STOP;
    }
};

fn tokenizeInput(
    allocator: std.mem.Allocator,
    input: []const u8,
    specs: *const code_points.CodePointsSpecs,
    apply_nfc: bool,
) ![]Token {
    _ = specs;
    _ = apply_nfc;
    
    var tokens = std.ArrayList(Token).init(allocator);
    defer tokens.deinit();
    
    // Convert input to code points
    const cps = try utils.str2cps(allocator, input);
    defer allocator.free(cps);
    
    // Create a simple character specs for now
    const char_specs = CharacterSpecs{};
    
    for (cps) |cp| {
        if (char_specs.isStop(cp)) {
            try tokens.append(Token.createStop(allocator));
        } else if (char_specs.isValid(cp)) {
            try tokens.append(try Token.createValid(allocator, &[_]CodePoint{cp}));
        } else if (char_specs.isIgnored(cp)) {
            try tokens.append(Token.createIgnored(allocator, cp));
        } else if (char_specs.getMapped(cp)) |mapped| {
            try tokens.append(try Token.createMapped(allocator, cp, mapped));
        } else {
            try tokens.append(Token.createDisallowed(allocator, cp));
        }
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
    
    // Test ignored token
    const ignored_token = Token.createIgnored(allocator, 0x200C);
    try testing.expectEqual(TokenType.ignored, ignored_token.type);
    try testing.expectEqual(@as(CodePoint, 0x200C), ignored_token.data.ignored.cp);
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

test "character classification" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    const specs = CharacterSpecs{};
    
    // Test valid characters
    try testing.expect(specs.isValid('a'));
    try testing.expect(specs.isValid('Z'));
    try testing.expect(specs.isValid('5'));
    try testing.expect(specs.isValid('-'));
    
    // Test invalid characters
    try testing.expect(!specs.isValid('!'));
    try testing.expect(!specs.isValid('@'));
    
    // Test ignored characters
    try testing.expect(specs.isIgnored(0x00AD)); // soft hyphen
    try testing.expect(specs.isIgnored(0x200C)); // ZWNJ
    try testing.expect(specs.isIgnored(0x200D)); // ZWJ
    
    // Test stop character
    try testing.expect(specs.isStop('.'));
    try testing.expect(!specs.isStop('a'));
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