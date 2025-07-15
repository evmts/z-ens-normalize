const root = @import("root.zig");
const CodePoint = root.CodePoint;

pub const CP_STOP: CodePoint = 0x2E;
pub const CP_FE0F: CodePoint = 0xFE0F;
pub const CP_APOSTROPHE: CodePoint = 8217;
pub const CP_SLASH: CodePoint = 8260;
pub const CP_MIDDLE_DOT: CodePoint = 12539;
pub const CP_XI_SMALL: CodePoint = 0x3BE;
pub const CP_XI_CAPITAL: CodePoint = 0x39E;
pub const CP_UNDERSCORE: CodePoint = 0x5F;
pub const CP_HYPHEN: CodePoint = 0x2D;
pub const CP_ZERO_WIDTH_JOINER: CodePoint = 0x200D;
pub const CP_ZERO_WIDTH_NON_JOINER: CodePoint = 0x200C;

pub const GREEK_GROUP_NAME: []const u8 = "Greek";
pub const MAX_EMOJI_LEN: usize = 0x2d;
pub const STR_FE0F: []const u8 = "\u{fe0f}";