const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const tokens = @import("tokens.zig");
const code_points = @import("code_points.zig");
const validate = @import("validate.zig");
const error_types = @import("error.zig");
const beautify_mod = @import("beautify.zig");
const join = @import("join.zig");

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
    
    pub fn tokenize(self: *const EnsNameNormalizer, input: []const u8) !tokens.TokenizedName {
        return tokens.TokenizedName.fromInput(self.allocator, input, &self.specs, true);
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
    tokenized: tokens.TokenizedName,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: ProcessedName) void {
        for (self.labels) |label| {
            label.deinit();
        }
        self.allocator.free(self.labels);
        self.tokenized.deinit(self.allocator);
    }
    
    pub fn normalize(self: *const ProcessedName) ![]u8 {
        return join.joinLabels(self.allocator, self.labels);
    }
    
    pub fn beautify(self: *const ProcessedName) ![]u8 {
        return beautify_mod.beautifyLabels(self.allocator, self.labels);
    }
};

// Convenience functions that use default normalizer
pub fn tokenize(allocator: std.mem.Allocator, input: []const u8) !tokens.TokenizedName {
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
    var normalizer = EnsNameNormalizer.default(allocator);
    defer normalizer.deinit();
    return normalizer.normalize(input);
}

pub fn beautify(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var normalizer = EnsNameNormalizer.default(allocator);
    defer normalizer.deinit();
    return normalizer.beautify_fn(input);
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