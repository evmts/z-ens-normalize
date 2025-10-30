const std = @import("std");
const Allocator = std.mem.Allocator;
const Decoder = @import("../util/decoder.zig").Decoder;
const RuneSet = @import("../util/runeset.zig").RuneSet;

/// Embed the compressed normalization data
const compressed = @embedFile("nf.bin");

// Packing constants for combining class and codepoint into single value
// Format: [CC: 8 bits][CP: 24 bits]
const SHIFT: u5 = 24;
const MASK: u21 = (1 << SHIFT) - 1;
const NONE: i32 = -1;

// Hangul syllable constants for algorithmic decomposition/composition
const S0: u21 = 0xAC00; // First Hangul syllable
const L0: u21 = 0x1100; // First leading consonant (Choseong)
const V0: u21 = 0x1161; // First vowel (Jungseong)
const T0: u21 = 0x11A7; // First trailing consonant (Jongseong)
const L_COUNT: u21 = 19; // Number of leading consonants
const V_COUNT: u21 = 21; // Number of vowels
const T_COUNT: u21 = 28; // Number of trailing consonants
const N_COUNT: u21 = V_COUNT * T_COUNT; // 588
const S_COUNT: u21 = L_COUNT * N_COUNT; // 11172 - total Hangul syllables
const S1: u21 = S0 + S_COUNT; // One past last Hangul syllable
const L1: u21 = L0 + L_COUNT;
const V1: u21 = V0 + V_COUNT;
const T1: u21 = T0 + T_COUNT;

// Helper function: Check if codepoint is a Hangul syllable
fn isHangul(cp: u21) bool {
    return cp >= S0 and cp < S1;
}

// Helper function: Extract combining class from packed value
fn unpackCC(packed_val: i32) u8 {
    const upacked: u32 = @bitCast(packed_val);
    return @intCast((upacked >> SHIFT) & 0xFF);
}

// Helper function: Extract codepoint from packed value
fn unpackCP(packed_val: i32) u21 {
    const upacked: u32 = @bitCast(packed_val);
    return @intCast(upacked & MASK);
}

// NF struct: Holds all Unicode normalization data
pub const NF = struct {
    unicodeVersion: []const u8,
    exclusions: RuneSet,
    quickCheck: RuneSet,
    decomps: std.AutoHashMap(u21, []u21),
    recomps: std.AutoHashMap(u21, std.AutoHashMap(u21, u21)),
    ranks: std.AutoHashMap(u21, u8),

    /// Initialize NF by decoding the embedded nf.bin data
    /// This loads all normalization tables needed for NFC/NFD operations
    pub fn init(allocator: Allocator) !NF {
        // Initialize decoder from embedded binary data
        var decoder = try Decoder.init(compressed, allocator);

        // Read unicode version string
        const unicodeVersion = try decoder.ReadString(allocator);
        errdefer allocator.free(unicodeVersion);

        // Read exclusions set
        const exclusions_ints = try decoder.ReadUnique(allocator);
        defer allocator.free(exclusions_ints);
        const exclusions = try RuneSet.fromInts(allocator, exclusions_ints);
        errdefer exclusions.deinit(allocator);

        // Read quickCheck set
        const quickcheck_ints = try decoder.ReadUnique(allocator);
        defer allocator.free(quickcheck_ints);
        const quickCheck = try RuneSet.fromInts(allocator, quickcheck_ints);
        errdefer quickCheck.deinit(allocator);

        // Initialize maps
        var decomps = std.AutoHashMap(u21, []u21).init(allocator);
        errdefer {
            var decomps_iter = decomps.iterator();
            while (decomps_iter.next()) |entry| {
                allocator.free(entry.value_ptr.*);
            }
            decomps.deinit();
        }

        var recomps = std.AutoHashMap(u21, std.AutoHashMap(u21, u21)).init(allocator);
        errdefer {
            var recomps_iter = recomps.iterator();
            while (recomps_iter.next()) |entry| {
                entry.value_ptr.deinit();
            }
            recomps.deinit();
        }

        var ranks = std.AutoHashMap(u21, u8).init(allocator);
        errdefer ranks.deinit();

        // Phase 1 - Read 1-character decompositions
        const decomp1 = try decoder.ReadSortedUnique(allocator);
        defer allocator.free(decomp1);
        const decomp1A = try decoder.ReadUnsortedDeltas(@intCast(decomp1.len), allocator);
        defer allocator.free(decomp1A);

        for (decomp1, decomp1A) |cp, target| {
            const decomp = try allocator.alloc(u21, 1);
            decomp[0] = @intCast(target);
            try decomps.put(@intCast(cp), decomp);
        }

        // Phase 2 - Read 2-character decompositions
        const decomp2 = try decoder.ReadSortedUnique(allocator);
        defer allocator.free(decomp2);
        const decomp2A = try decoder.ReadUnsortedDeltas(@intCast(decomp2.len), allocator);
        defer allocator.free(decomp2A);
        const decomp2B = try decoder.ReadUnsortedDeltas(@intCast(decomp2.len), allocator);
        defer allocator.free(decomp2B);

        for (decomp2, decomp2A, decomp2B) |cp, targetA, targetB| {
            const cp_u21: u21 = @intCast(cp);
            const cpA: u21 = @intCast(targetA);
            const cpB: u21 = @intCast(targetB);

            // Build decomps map: cp -> [cpB, cpA] (Note: B comes first!)
            const decomp = try allocator.alloc(u21, 2);
            decomp[0] = cpB;
            decomp[1] = cpA;
            try decomps.put(cp_u21, decomp);

            // Build recomps map (only if not excluded)
            if (!exclusions.contains(cp_u21)) {
                // Get or create inner map for cpA
                var entry = try recomps.getOrPut(cpA);
                if (!entry.found_existing) {
                    entry.value_ptr.* = std.AutoHashMap(u21, u21).init(allocator);
                }
                // Map cpB -> cp in the inner map
                try entry.value_ptr.put(cpB, cp_u21);
            }
        }

        // Read ranks data (infinite loop until empty array)
        var rank_value: u8 = 1;
        while (true) : (rank_value += 1) {
            const cps = try decoder.ReadUnique(allocator);
            defer allocator.free(cps);

            if (cps.len == 0) break;

            for (cps) |cp| {
                try ranks.put(@intCast(cp), rank_value);
            }
        }

        // Assert we've consumed all data
        decoder.assertEOF();

        // Clean up decoder's allocated memory
        decoder.deinit(allocator);

        return NF{
            .unicodeVersion = unicodeVersion,
            .exclusions = exclusions,
            .quickCheck = quickCheck,
            .decomps = decomps,
            .recomps = recomps,
            .ranks = ranks,
        };
    }

    // Packer struct: Accumulates decomposed codepoints with combining classes
    const Packer = struct {
        nf: *const NF,
        buf: std.ArrayList(i32),
        check: bool,

        // Add codepoint to buffer, packing with combining class if present
        fn add(self: *Packer, cp: u21) void {
            _ = self;
            _ = cp;
            unreachable;
        }

        // Reorder codepoints by combining class (canonical ordering)
        fn fixOrder(self: *Packer) void {
            _ = self;
            unreachable;
        }
    };

    // Attempt to compose two codepoints into a single codepoint
    // Handles Hangul algorithmic composition and table-based composition
    fn composePair(self: *const NF, a: u21, b: u21) i32 {
        _ = self;
        _ = a;
        _ = b;
        unreachable;
    }

    // Recursively decompose codepoints with Hangul special handling
    // Returns packed values (CP + CC in single i32)
    fn decomposed(self: *const NF, allocator: Allocator, cps: []const u21) ![]i32 {
        _ = self;
        _ = allocator;
        _ = cps;
        unreachable;
    }

    // Recompose decomposed+packed codepoints while respecting blocking rules
    fn composedFromPacked(self: *const NF, allocator: Allocator, packed_cps: []const i32) ![]u21 {
        _ = self;
        _ = allocator;
        _ = packed_cps;
        unreachable;
    }

    // Public method: NFD (Canonical Decomposition)
    // Decomposes all characters to their canonical decomposed form
    pub fn nfd(self: *const NF, allocator: Allocator, cps: []const u21) ![]u21 {
        _ = self;
        _ = allocator;
        _ = cps;
        unreachable;
    }

    // Public method: NFC (Canonical Composition)
    // Decomposes then recomposes where possible
    pub fn nfc(self: *const NF, allocator: Allocator, cps: []const u21) ![]u21 {
        _ = self;
        _ = allocator;
        _ = cps;
        unreachable;
    }

    // Cleanup method: Free all allocated memory
    pub fn deinit(self: *NF, allocator: Allocator) void {
        // Free unicode version string
        allocator.free(self.unicodeVersion);

        // Free RuneSets
        self.exclusions.deinit(allocator);
        self.quickCheck.deinit(allocator);

        // Free decomps map and all allocated slices
        var decomps_iter = self.decomps.iterator();
        while (decomps_iter.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        self.decomps.deinit();

        // Free recomps map and all nested maps
        var recomps_iter = self.recomps.iterator();
        while (recomps_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.recomps.deinit();

        // Free ranks map
        self.ranks.deinit();
    }
};
