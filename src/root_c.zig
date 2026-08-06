// C FFI bindings for z-ens-normalize
const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");

// Freestanding wasm has no OS to back GeneralPurposeAllocator's debug
// machinery (thread ids, stack traces); use the purpose-built wasm
// allocator there instead.
const use_wasm_allocator = builtin.target.cpu.arch.isWasm() and
    builtin.target.os.tag == .freestanding;

// GeneralPurposeAllocator is a debug allocator; keep it (and its leak
// detection on zens_deinit) for Debug builds, but serve release builds
// from the faster lock-free smp_allocator.
const use_smp_allocator = !use_wasm_allocator and builtin.mode != .Debug and
    !builtin.single_threaded;

// Error codes for C API
pub const ZensError = enum(c_int) {
    Success = 0,
    OutOfMemory = -1,
    InvalidUtf8 = -2,
    InvalidLabelExtension = -3,
    IllegalMixture = -4,
    WholeConfusable = -5,
    LeadingUnderscore = -6,
    FencedLeading = -7,
    FencedAdjacent = -8,
    FencedTrailing = -9,
    DisallowedCharacter = -10,
    EmptyLabel = -11,
    CMLeading = -12,
    CMAfterEmoji = -13,
    NSMDuplicate = -14,
    NSMExcessive = -15,
    UnknownError = -99,

    pub fn fromError(err: anyerror) ZensError {
        return switch (err) {
            error.OutOfMemory => .OutOfMemory,
            error.InvalidUtf8 => .InvalidUtf8,
            error.InvalidLabelExtension => .InvalidLabelExtension,
            error.IllegalMixture => .IllegalMixture,
            error.WholeConfusable => .WholeConfusable,
            error.LeadingUnderscore => .LeadingUnderscore,
            error.FencedLeading => .FencedLeading,
            error.FencedAdjacent => .FencedAdjacent,
            error.FencedTrailing => .FencedTrailing,
            error.DisallowedCharacter => .DisallowedCharacter,
            error.EmptyLabel => .EmptyLabel,
            error.CMLeading => .CMLeading,
            error.CMAfterEmoji => .CMAfterEmoji,
            error.NSMDuplicate => .NSMDuplicate,
            error.NSMExcessive => .NSMExcessive,
            else => .UnknownError,
        };
    }
};

// Opaque allocator handle for C API
const ZensAllocator = opaque {};

// Result struct for C API
pub const ZensResult = extern struct {
    data: ?[*]u8,
    len: usize,
    error_code: c_int,
};

// Global allocator for the C API. DebugAllocator (the 0.16 name for
// GeneralPurposeAllocator) is statically initializable and thread-safe,
// so no lazy-init lock is needed.
var debug_allocator: std.heap.DebugAllocator(.{}) = .{};

fn getGlobalAllocator() std.mem.Allocator {
    if (comptime use_wasm_allocator) {
        return std.heap.wasm_allocator;
    } else if (comptime use_smp_allocator) {
        return std.heap.smp_allocator;
    } else {
        return debug_allocator.allocator();
    }
}

/// Initialize the library (optional, but recommended to call once)
/// Returns 0 on success, non-zero on failure
export fn zens_init() c_int {
    _ = getGlobalAllocator();
    return 0;
}

/// Cleanup the library (call at program exit)
export fn zens_deinit() void {
    if (comptime use_wasm_allocator or use_smp_allocator) return;

    _ = debug_allocator.deinit();
    debug_allocator = .{};
}

/// Normalize an ENS name
///
/// @param input: Input name as UTF-8 bytes (null-terminated)
/// @param input_len: Length of input (or 0 to use strlen)
/// @return ZensResult with normalized name or error
export fn zens_normalize(input: [*c]const u8, input_len: usize) ZensResult {
    if (input == null) {
        return ZensResult{
            .data = null,
            .len = 0,
            .error_code = @intFromEnum(ZensError.InvalidUtf8),
        };
    }

    const allocator = getGlobalAllocator();

    // Determine input length
    const len = if (input_len == 0) std.mem.len(input) else input_len;
    const input_slice = input[0..len];

    const result = root.normalize(allocator, input_slice) catch |err| {
        return ZensResult{
            .data = null,
            .len = 0,
            .error_code = @intFromEnum(ZensError.fromError(err)),
        };
    };

    return ZensResult{
        .data = result.ptr,
        .len = result.len,
        .error_code = @intFromEnum(ZensError.Success),
    };
}

/// Beautify an ENS name
///
/// @param input: Input name as UTF-8 bytes (null-terminated)
/// @param input_len: Length of input (or 0 to use strlen)
/// @return ZensResult with beautified name or error
export fn zens_beautify(input: [*c]const u8, input_len: usize) ZensResult {
    if (input == null) {
        return ZensResult{
            .data = null,
            .len = 0,
            .error_code = @intFromEnum(ZensError.InvalidUtf8),
        };
    }

    const allocator = getGlobalAllocator();

    // Determine input length
    const len = if (input_len == 0) std.mem.len(input) else input_len;
    const input_slice = input[0..len];

    const result = root.beautify(allocator, input_slice) catch |err| {
        return ZensResult{
            .data = null,
            .len = 0,
            .error_code = @intFromEnum(ZensError.fromError(err)),
        };
    };

    return ZensResult{
        .data = result.ptr,
        .len = result.len,
        .error_code = @intFromEnum(ZensError.Success),
    };
}

/// Free memory allocated by zens_normalize or zens_beautify
///
/// @param result: Result struct from zens_normalize or zens_beautify
export fn zens_free(result: ZensResult) void {
    if (result.data) |ptr| {
        const allocator = getGlobalAllocator();
        const slice = ptr[0..result.len];
        allocator.free(slice);
    }
}

/// Get error message for error code
///
/// @param error_code: Error code from ZensResult
/// @return Null-terminated error message string (do not free)
export fn zens_error_message(error_code: c_int) [*c]const u8 {
    const err: ZensError = @enumFromInt(error_code);
    return switch (err) {
        .Success => "Success",
        .OutOfMemory => "Out of memory",
        .InvalidUtf8 => "Invalid UTF-8 encoding",
        .InvalidLabelExtension => "Invalid label extension (-- at positions 2-3)",
        .IllegalMixture => "Illegal script mixture",
        .WholeConfusable => "Whole confusable",
        .LeadingUnderscore => "Leading underscore",
        .FencedLeading => "Fenced leading",
        .FencedAdjacent => "Fenced adjacent",
        .FencedTrailing => "Fenced trailing",
        .DisallowedCharacter => "Disallowed character",
        .EmptyLabel => "Empty label",
        .CMLeading => "Combining mark leading",
        .CMAfterEmoji => "Combining mark after emoji",
        .NSMDuplicate => "Non-spacing mark duplicate",
        .NSMExcessive => "Non-spacing mark excessive",
        .UnknownError => "Unknown error",
    };
}

// ============================================================
// Buffer helpers (primarily for WASM hosts, usable from C too)
// ============================================================
// WASM hosts have no libc malloc, and ZensResult is returned by
// value (which does not cross the wasm C ABI as a plain return),
// so provide explicit buffer management and pointer-based variants.
// The wasm linear memory itself is exported by the linker as
// "memory" (see build.zig).

/// Allocate a buffer the host can write input bytes into.
/// Returns null on allocation failure.
export fn zens_alloc(len: usize) ?[*]u8 {
    const allocator = getGlobalAllocator();
    const buf = allocator.alloc(u8, len) catch return null;
    return buf.ptr;
}

/// Free a buffer allocated with zens_alloc (len must match).
export fn zens_dealloc(ptr: ?[*]u8, len: usize) void {
    if (ptr) |p| {
        const allocator = getGlobalAllocator();
        allocator.free(p[0..len]);
    }
}

/// Normalize, writing the result struct through a caller-provided pointer.
export fn zens_normalize_into(result: *ZensResult, input: [*c]const u8, input_len: usize) void {
    result.* = zens_normalize(input, input_len);
}

/// Beautify, writing the result struct through a caller-provided pointer.
export fn zens_beautify_into(result: *ZensResult, input: [*c]const u8, input_len: usize) void {
    result.* = zens_beautify(input, input_len);
}

/// Free the data of a result produced by the _into variants.
export fn zens_free_result(result: *const ZensResult) void {
    zens_free(result.*);
}
