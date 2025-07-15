const std = @import("std");
const testing = std.testing;

pub const CodePoint = u32;

pub const beautify = @import("beautify.zig");
pub const code_points = @import("code_points.zig");
pub const constants = @import("constants.zig");
pub const error_types = @import("error.zig");
pub const join = @import("join.zig");
pub const normalizer = @import("normalizer.zig");
pub const static_data = @import("static_data.zig");
pub const tokens = @import("tokens.zig");
pub const tokenizer = @import("tokenizer.zig");
pub const utils = @import("utils.zig");
pub const validate = @import("validate.zig");
pub const validator = @import("validator.zig");

// Re-export main API
pub const EnsNameNormalizer = normalizer.EnsNameNormalizer;
pub const ProcessedName = normalizer.ProcessedName;
pub const ProcessError = error_types.ProcessError;
pub const CurrableError = error_types.CurrableError;
pub const DisallowedSequence = error_types.DisallowedSequence;
pub const ValidatedLabel = validate.ValidatedLabel;
pub const LabelType = validate.LabelType;

// Re-export convenience functions
pub const normalize = normalizer.normalize;
pub const beautify_fn = normalizer.beautify;
pub const process = normalizer.process;
pub const tokenize = normalizer.tokenize;

test {
    testing.refAllDecls(@This());
}