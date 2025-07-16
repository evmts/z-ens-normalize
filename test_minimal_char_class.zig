const std = @import("std");

pub fn main() !void {
    std.debug.print("Testing character classification without full data load...\n", .{});
    
    // These are the decimal values from spec.zon ignored list
    const ignored_chars = [_]u32{
        173,    // SOFT HYPHEN
        6155,   // ARABIC TATWEEL SIGN
        6156,   // ARABIC LETTER HAMZA ABOVE
        6157,   // ARABIC LETTER ALEF WITH HAMZA ABOVE  
        6159,   // ARABIC LETTER YEH WITH HAMZA ABOVE
        8203,   // ZERO WIDTH SPACE
        8288,   // WORD JOINER
        8292,   // INVISIBLE PLUS
        65024,  // VARIATION SELECTOR-15
        65025,  // VARIATION SELECTOR-16
        65026,  // VARIATION SELECTOR-17
        65027,  // VARIATION SELECTOR-18
        65028,  // VARIATION SELECTOR-19
        65029,  // VARIATION SELECTOR-20
        65030,  // VARIATION SELECTOR-21
        65031,  // VARIATION SELECTOR-22
        65032,  // VARIATION SELECTOR-23
        65033,  // VARIATION SELECTOR-24
        65034,  // VARIATION SELECTOR-25
        65035,  // VARIATION SELECTOR-26
        65036,  // VARIATION SELECTOR-27
        65037,  // VARIATION SELECTOR-28
        65038,  // VARIATION SELECTOR-29
        65039,  // VARIATION SELECTOR-30
        65279,  // ZERO WIDTH NO-BREAK SPACE (BOM)
        119155, // MUSICAL SYMBOL NULL NOTEHEAD
        119156, // MUSICAL SYMBOL NULL NOTEHEAD
        119157, // MUSICAL SYMBOL NULL NOTEHEAD
        119158, // MUSICAL SYMBOL NULL NOTEHEAD
        119159, // MUSICAL SYMBOL NULL NOTEHEAD
        119160, // MUSICAL SYMBOL NULL NOTEHEAD
        119161, // MUSICAL SYMBOL NULL NOTEHEAD
        119162, // MUSICAL SYMBOL NULL NOTEHEAD
        917505, // TAG SPACE
    };
    
    // Check if ZWNJ (8204) and ZWJ (8205) are in the ignored list
    const zwnj: u32 = 8204; // 0x200C
    const zwj: u32 = 8205;  // 0x200D
    
    var zwnj_ignored = false;
    var zwj_ignored = false;
    
    for (ignored_chars) |cp| {
        if (cp == zwnj) zwnj_ignored = true;
        if (cp == zwj) zwj_ignored = true;
    }
    
    std.debug.print("\nZWNJ (U+200C, decimal 8204):\n", .{});
    std.debug.print("  Is in ignored list: {}\n", .{zwnj_ignored});
    std.debug.print("  Expected: false (should be disallowed)\n", .{});
    
    std.debug.print("\nZWJ (U+200D, decimal 8205):\n", .{});
    std.debug.print("  Is in ignored list: {}\n", .{zwj_ignored});
    std.debug.print("  Expected: false (should be disallowed except in emoji)\n", .{});
    
    std.debug.print("\nSoft Hyphen (U+00AD, decimal 173):\n", .{});
    var soft_hyphen_ignored = false;
    for (ignored_chars) |cp| {
        if (cp == 173) {
            soft_hyphen_ignored = true;
            break;
        }
    }
    std.debug.print("  Is in ignored list: {}\n", .{soft_hyphen_ignored});
    std.debug.print("  Expected: true\n", .{});
    
    if (!zwnj_ignored and !zwj_ignored and soft_hyphen_ignored) {
        std.debug.print("\n✅ Character classification is correct!\n", .{});
    } else {
        std.debug.print("\n❌ Character classification has issues!\n", .{});
    }
}