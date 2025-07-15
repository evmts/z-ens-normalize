const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const constants = @import("constants.zig");
const utils = @import("utils.zig");

pub const EnsNameToken = union(enum) {
    valid: TokenValid,
    mapped: TokenMapped,
    ignored: TokenIgnored,
    disallowed: TokenDisallowed,
    stop: TokenStop,
    nfc: TokenNfc,
    emoji: TokenEmoji,
    
    pub fn getCps(self: EnsNameToken, allocator: std.mem.Allocator) ![]CodePoint {
        switch (self) {
            .valid => |t| return allocator.dupe(CodePoint, t.cps),
            .mapped => |t| return allocator.dupe(CodePoint, t.cps),
            .nfc => |t| return allocator.dupe(CodePoint, t.cps),
            .emoji => |t| return allocator.dupe(CodePoint, t.cps_no_fe0f),
            .disallowed => |t| {
                var result = try allocator.alloc(CodePoint, 1);
                result[0] = t.cp;
                return result;
            },
            .stop => |t| {
                var result = try allocator.alloc(CodePoint, 1);
                result[0] = t.cp;
                return result;
            },
            .ignored => |t| {
                var result = try allocator.alloc(CodePoint, 1);
                result[0] = t.cp;
                return result;
            },
        }
    }
    
    pub fn getInputSize(self: EnsNameToken) usize {
        switch (self) {
            .valid => |t| return t.cps.len,
            .nfc => |t| return t.input.len,
            .emoji => |t| return t.cps_input.len,
            .mapped, .disallowed, .ignored, .stop => return 1,
        }
    }
    
    pub fn isText(self: EnsNameToken) bool {
        return switch (self) {
            .valid, .mapped, .nfc => true,
            else => false,
        };
    }
    
    pub fn isEmoji(self: EnsNameToken) bool {
        return switch (self) {
            .emoji => true,
            else => false,
        };
    }
    
    pub fn isIgnored(self: EnsNameToken) bool {
        return switch (self) {
            .ignored => true,
            else => false,
        };
    }
    
    pub fn isDisallowed(self: EnsNameToken) bool {
        return switch (self) {
            .disallowed => true,
            else => false,
        };
    }
    
    pub fn isStop(self: EnsNameToken) bool {
        return switch (self) {
            .stop => true,
            else => false,
        };
    }
    
    pub fn createStop() EnsNameToken {
        return EnsNameToken{ .stop = TokenStop{ .cp = constants.CP_STOP } };
    }
    
    pub fn asString(self: EnsNameToken, allocator: std.mem.Allocator) ![]u8 {
        const cps = try self.getCps(allocator);
        defer allocator.free(cps);
        return utils.cps2str(allocator, cps);
    }
};

pub const TokenValid = struct {
    cps: []const CodePoint,
};

pub const TokenMapped = struct {
    cps: []const CodePoint,
    cp: CodePoint,
};

pub const TokenIgnored = struct {
    cp: CodePoint,
};

pub const TokenDisallowed = struct {
    cp: CodePoint,
};

pub const TokenStop = struct {
    cp: CodePoint,
};

pub const TokenNfc = struct {
    cps: []const CodePoint,
    input: []const CodePoint,
};

pub const TokenEmoji = struct {
    input: []const u8,
    emoji: []const CodePoint,
    cps_input: []const CodePoint,
    cps_no_fe0f: []const CodePoint,
};

pub const CollapsedEnsNameToken = union(enum) {
    text: TokenValid,
    emoji: TokenEmoji,
    
    pub fn getInputSize(self: CollapsedEnsNameToken) usize {
        switch (self) {
            .text => |t| return t.cps.len,
            .emoji => |t| return t.cps_input.len,
        }
    }
};

pub const TokenizedName = struct {
    tokens: []const EnsNameToken,
    
    pub fn deinit(self: TokenizedName, allocator: std.mem.Allocator) void {
        allocator.free(self.tokens);
    }
    
    pub fn fromInput(
        allocator: std.mem.Allocator,
        input: []const u8,
        specs: anytype,
        should_nfc: bool,
    ) !TokenizedName {
        // This is a placeholder implementation
        // The actual tokenization logic would need to be implemented
        // based on the Rust implementation
        _ = specs;
        _ = should_nfc;
        
        var tokens = std.ArrayList(EnsNameToken).init(allocator);
        defer tokens.deinit();
        
        // Basic tokenization - convert string to code points
        const cps = try utils.str2cps(allocator, input);
        defer allocator.free(cps);
        
        // Create a single valid token for now
        const owned_cps = try allocator.dupe(CodePoint, cps);
        try tokens.append(EnsNameToken{ .valid = TokenValid{ .cps = owned_cps } });
        
        return TokenizedName{
            .tokens = try tokens.toOwnedSlice(),
        };
    }
};

test "EnsNameToken basic operations" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    
    const stop_token = EnsNameToken.createStop();
    try testing.expect(stop_token.isStop());
    try testing.expect(!stop_token.isText());
    try testing.expect(!stop_token.isEmoji());
    
    const input_size = stop_token.getInputSize();
    try testing.expectEqual(@as(usize, 1), input_size);
}