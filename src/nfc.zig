const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const static_data_loader = @import("static_data_loader.zig");

// NFC Data structure to hold normalization data
pub const NFCData = struct {
    // Decomposition mappings
    decomp: std.AutoHashMap(CodePoint, []const CodePoint),
    // Recomposition mappings (pair of codepoints -> single codepoint)
    recomp: std.AutoHashMap(CodePointPair, CodePoint),
    // Exclusions set
    exclusions: std.AutoHashMap(CodePoint, void),
    // Combining class rankings
    combining_class: std.AutoHashMap(CodePoint, u8),
    // Characters that need NFC checking
    nfc_check: std.AutoHashMap(CodePoint, void),
    allocator: std.mem.Allocator,
    
    pub const CodePointPair = struct {
        first: CodePoint,
        second: CodePoint,
        
        pub fn hash(self: CodePointPair) u64 {
            var hasher = std.hash.Wyhash.init(0);
            hasher.update(std.mem.asBytes(&self.first));
            hasher.update(std.mem.asBytes(&self.second));
            return hasher.final();
        }
        
        pub fn eql(a: CodePointPair, b: CodePointPair) bool {
            return a.first == b.first and a.second == b.second;
        }
    };
    
    pub fn init(allocator: std.mem.Allocator) NFCData {
        return NFCData{
            .decomp = std.AutoHashMap(CodePoint, []const CodePoint).init(allocator),
            .recomp = std.AutoHashMap(CodePointPair, CodePoint).init(allocator),
            .exclusions = std.AutoHashMap(CodePoint, void).init(allocator),
            .combining_class = std.AutoHashMap(CodePoint, u8).init(allocator),
            .nfc_check = std.AutoHashMap(CodePoint, void).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *NFCData) void {
        // Free decomposition values
        var decomp_iter = self.decomp.iterator();
        while (decomp_iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.*);
        }
        self.decomp.deinit();
        self.recomp.deinit();
        self.exclusions.deinit();
        self.combining_class.deinit();
        self.nfc_check.deinit();
    }
    
    pub fn requiresNFCCheck(self: *const NFCData, cp: CodePoint) bool {
        return self.nfc_check.contains(cp);
    }
    
    pub fn getCombiningClass(self: *const NFCData, cp: CodePoint) u8 {
        return self.combining_class.get(cp) orelse 0;
    }
};

// Hangul syllable constants (from JavaScript reference)
const S0: CodePoint = 0xAC00;
const L0: CodePoint = 0x1100;
const V0: CodePoint = 0x1161;
const T0: CodePoint = 0x11A7;
const L_COUNT: CodePoint = 19;
const V_COUNT: CodePoint = 21;
const T_COUNT: CodePoint = 28;
const N_COUNT: CodePoint = V_COUNT * T_COUNT;
const S_COUNT: CodePoint = L_COUNT * N_COUNT;
const S1: CodePoint = S0 + S_COUNT;
const L1: CodePoint = L0 + L_COUNT;
const V1: CodePoint = V0 + V_COUNT;
const T1: CodePoint = T0 + T_COUNT;

pub fn isHangul(cp: CodePoint) bool {
    return cp >= S0 and cp < S1;
}

// Decompose a single Hangul syllable
pub fn decomposeHangul(cp: CodePoint, result: *std.ArrayList(CodePoint)) !void {
    if (!isHangul(cp)) return;
    
    const s_index = cp - S0;
    const l_index = s_index / N_COUNT;
    const v_index = (s_index % N_COUNT) / T_COUNT;
    const t_index = s_index % T_COUNT;
    
    try result.append(L0 + l_index);
    try result.append(V0 + v_index);
    if (t_index > 0) {
        try result.append(T0 + t_index);
    }
}

// Compose Hangul syllables
pub fn composeHangul(a: CodePoint, b: CodePoint) ?CodePoint {
    // L + V
    if (a >= L0 and a < L1 and b >= V0 and b < V1) {
        return S0 + (a - L0) * N_COUNT + (b - V0) * T_COUNT;
    }
    // LV + T
    if (isHangul(a) and b > T0 and b < T1 and (a - S0) % T_COUNT == 0) {
        return a + (b - T0);
    }
    return null;
}

// Decompose a string of codepoints
pub fn decompose(allocator: std.mem.Allocator, cps: []const CodePoint, nfc_data: *const NFCData) ![]CodePoint {
    var result = std.ArrayList(CodePoint).init(allocator);
    defer result.deinit();
    
    for (cps) |cp| {
        // Check for Hangul syllable
        if (isHangul(cp)) {
            try decomposeHangul(cp, &result);
        } else if (nfc_data.decomp.get(cp)) |decomposed| {
            // Recursive decomposition
            const sub_decomposed = try decompose(allocator, decomposed, nfc_data);
            defer allocator.free(sub_decomposed);
            try result.appendSlice(sub_decomposed);
        } else {
            // No decomposition
            try result.append(cp);
        }
    }
    
    // Apply canonical ordering
    try canonicalOrder(result.items, nfc_data);
    
    return result.toOwnedSlice();
}

// Apply canonical ordering based on combining classes
fn canonicalOrder(cps: []CodePoint, nfc_data: *const NFCData) !void {
    if (cps.len <= 1) return;
    
    // Bubble sort for canonical ordering (stable sort)
    var i: usize = 1;
    while (i < cps.len) : (i += 1) {
        const cc = nfc_data.getCombiningClass(cps[i]);
        if (cc != 0) {
            var j = i;
            while (j > 0) : (j -= 1) {
                const prev_cc = nfc_data.getCombiningClass(cps[j - 1]);
                if (prev_cc == 0 or prev_cc <= cc) break;
                
                // Swap
                const tmp = cps[j];
                cps[j] = cps[j - 1];
                cps[j - 1] = tmp;
            }
        }
    }
}

// Compose a string of decomposed codepoints
pub fn compose(allocator: std.mem.Allocator, decomposed: []const CodePoint, nfc_data: *const NFCData) ![]CodePoint {
    if (decomposed.len == 0) {
        return try allocator.alloc(CodePoint, 0);
    }
    
    var result = std.ArrayList(CodePoint).init(allocator);
    defer result.deinit();
    
    var i: usize = 0;
    while (i < decomposed.len) {
        const cp = decomposed[i];
        const cc = nfc_data.getCombiningClass(cp);
        
        // Try to compose with previous character
        if (result.items.len > 0 and cc == 0) {
            const last_cp = result.items[result.items.len - 1];
            const last_cc = nfc_data.getCombiningClass(last_cp);
            
            if (last_cc == 0) {
                // Try Hangul composition first
                if (composeHangul(last_cp, cp)) |composed| {
                    result.items[result.items.len - 1] = composed;
                    i += 1;
                    continue;
                }
                
                // Try regular composition
                const pair = NFCData.CodePointPair{ .first = last_cp, .second = cp };
                if (nfc_data.recomp.get(pair)) |composed| {
                    if (!nfc_data.exclusions.contains(composed)) {
                        result.items[result.items.len - 1] = composed;
                        i += 1;
                        continue;
                    }
                }
            }
        }
        
        // No composition, just append
        try result.append(cp);
        i += 1;
    }
    
    return result.toOwnedSlice();
}

// Main NFC function
pub fn nfc(allocator: std.mem.Allocator, cps: []const CodePoint, nfc_data: *const NFCData) ![]CodePoint {
    // First decompose
    const decomposed = try decompose(allocator, cps, nfc_data);
    defer allocator.free(decomposed);
    
    // Then compose
    return try compose(allocator, decomposed, nfc_data);
}

// Check if codepoints need NFC normalization
pub fn needsNFC(cps: []const CodePoint, nfc_data: *const NFCData) bool {
    for (cps) |cp| {
        if (nfc_data.requiresNFCCheck(cp)) {
            return true;
        }
    }
    return false;
}

// Compare two codepoint arrays
pub fn compareCodePoints(a: []const CodePoint, b: []const CodePoint) bool {
    if (a.len != b.len) return false;
    for (a, b) |cp_a, cp_b| {
        if (cp_a != cp_b) return false;
    }
    return true;
}

test "Hangul decomposition" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var result = std.ArrayList(CodePoint).init(allocator);
    
    // Test Hangul syllable 가 (GA)
    try decomposeHangul(0xAC00, &result);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{ 0x1100, 0x1161 }, result.items);
    
    result.clearRetainingCapacity();
    
    // Test Hangul syllable 각 (GAK)
    try decomposeHangul(0xAC01, &result);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{ 0x1100, 0x1161, 0x11A8 }, result.items);
}

test "Hangul composition" {
    const testing = std.testing;
    
    // Test L + V
    try testing.expectEqual(@as(?CodePoint, 0xAC00), composeHangul(0x1100, 0x1161));
    
    // Test LV + T
    try testing.expectEqual(@as(?CodePoint, 0xAC01), composeHangul(0xAC00, 0x11A8));
    
    // Test invalid composition
    try testing.expectEqual(@as(?CodePoint, null), composeHangul(0x1100, 0x11A8));
}