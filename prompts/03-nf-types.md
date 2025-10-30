# Task 03: Port NF Types and Constants

## Goal

Port Unicode normalization data structures and Hangul constants from Go to Zig as `src/nf/nf.zig`. This file will contain the core data structures used for Unicode normalization (NFC/NFD) operations.

## Go Reference Code

From `/Users/williamcory/z-ens-normalize/go-ens-normalize/nf/nf.go` lines 12-51:

```go
const (
	SHIFT rune = 24
	MASK  rune = (1 << SHIFT) - 1
	NONE  rune = -1
)

const (
	S0      = 0xAC00
	L0      = 0x1100
	V0      = 0x1161
	T0      = 0x11A7
	L_COUNT = 19
	V_COUNT = 21
	T_COUNT = 28
	N_COUNT = V_COUNT * T_COUNT
	S_COUNT = L_COUNT * N_COUNT
	S1      = S0 + S_COUNT
	L1      = L0 + L_COUNT
	V1      = V0 + V_COUNT
	T1      = T0 + T_COUNT
)

func isHangul(cp rune) bool {
	return cp >= S0 && cp < S1
}
func unpackCC(packed rune) byte {
	return byte(packed >> SHIFT)
}
func unpackCP(packed rune) rune {
	return rune(packed & MASK)
}

type NF struct {
	unicodeVersion string
	exclusions     util.RuneSet
	quickCheck     util.RuneSet
	decomps        map[rune][]rune
	recomps        map[rune]map[rune]rune
	ranks          map[rune]byte
}
```

## Implementation Guidance

### Understanding the Constants

#### Packing Constants (SHIFT, MASK, NONE)

These constants are used for packing combining class (CC) and codepoint (CP) data into a single value:

- **SHIFT**: Bit position (24) where combining class starts in packed value
- **MASK**: Bitmask for extracting lower 24 bits (the codepoint)
- **NONE**: Sentinel value (-1) indicating absence of data

Format: `[CC: 8 bits][CP: 24 bits]`

In Zig:
```zig
const SHIFT: u5 = 24;
const MASK: u21 = (1 << SHIFT) - 1;
const NONE: i32 = -1;
```

#### Hangul Syllable Constants

Unicode Hangul syllables (Korean characters) are algorithmically decomposed/composed using these constants:

- **S0** (0xAC00): First Hangul syllable codepoint
- **L0** (0x1100): First Leading consonant (Choseong)
- **V0** (0x1161): First Vowel (Jungseong)
- **T0** (0x11A7): First Trailing consonant (Jongseong)
- **L_COUNT** (19): Number of leading consonants
- **V_COUNT** (21): Number of vowels
- **T_COUNT** (28): Number of trailing consonants
- **N_COUNT**: V_COUNT * T_COUNT (588)
- **S_COUNT**: L_COUNT * N_COUNT (11172) - total Hangul syllables
- **S1**: S0 + S_COUNT - one past last Hangul syllable
- **L1, V1, T1**: Similar bounds for L, V, T ranges

These enable algorithmic decomposition without lookup tables.

In Zig, declare as compile-time constants:
```zig
const S0: u21 = 0xAC00;
const L0: u21 = 0x1100;
// ... etc
```

### The NF Struct

The `NF` struct holds all normalization data loaded from the binary file:

- **unicodeVersion**: String identifying Unicode version (e.g., "15.0.0")
- **exclusions**: Set of codepoints excluded from composition
- **quickCheck**: Set of codepoints that can be quickly verified as already normalized
- **decomps**: Map from codepoint to its decomposition sequence
- **recomps**: Nested map for recomposition (first CP -> second CP -> result)
- **ranks**: Map from codepoint to its canonical combining class

In Zig, use appropriate standard library types:
```zig
const NF = struct {
    unicodeVersion: []const u8,
    exclusions: RuneSet,      // from util.runeset
    quickCheck: RuneSet,      // from util.runeset
    decomps: std.AutoHashMap(u21, []u21),
    recomps: std.AutoHashMap(u21, std.AutoHashMap(u21, u21)),
    ranks: std.AutoHashMap(u21, u8),

    // Methods will be added in later tasks
};
```

**Note**: The NF struct does not need to store an allocator because it references data embedded in the binary. The allocator will be passed to methods that need it.

### Helper Functions

Three utility functions for working with packed values and Hangul detection:

```zig
fn isHangul(cp: u21) bool {
    return cp >= S0 and cp < S1;
}

fn unpackCC(packed: i32) u8 {
    return @intCast(u8, @bitCast(u32, packed) >> SHIFT);
}

fn unpackCP(packed: i32) u21 {
    return @intCast(u21, @bitCast(u32, packed) & MASK);
}
```

**Implementation Note**: For now, implement these as stub functions with `@panic("TODO: implement")`. They will be properly implemented in later tasks.

## File Location

Create: `/Users/williamcory/z-ens-normalize/src/nf/nf.zig`

## Dependencies

This file depends on:

1. **`src/util/decoder.zig`**: For reading binary data from nf.bin (will be used in load methods)
2. **`src/util/runeset.zig`**: For RuneSet type used in exclusions and quickCheck fields
3. **Standard library**: `std.AutoHashMap` for maps

Import structure:
```zig
const std = @import("std");
const RuneSet = @import("../util/runeset.zig").RuneSet;
// Decoder will be imported in later tasks
```

## Success Criteria

- [ ] File `src/nf/nf.zig` exists
- [ ] All Hangul constants defined (S0, L0, V0, T0, L_COUNT, V_COUNT, T_COUNT, N_COUNT, S_COUNT, S1, L1, V1, T1)
- [ ] Packing constants defined (SHIFT, MASK, NONE)
- [ ] NF struct defined with all six fields (unicodeVersion, exclusions, quickCheck, decomps, recomps, ranks)
- [ ] Helper functions declared: `isHangul`, `unpackCC`, `unpackCP` (stubs with `@panic("TODO: implement")`)
- [ ] Proper imports from standard library and util modules
- [ ] File compiles without errors

## Validation Commands

After implementation, verify the code compiles:

```bash
zig build
```

This should succeed without errors.

## Common Pitfalls

### Type Selection

- **Rune type**: Use `u21` for Unicode codepoints (valid range 0x0 to 0x10FFFF)
- **Combining class**: Use `u8` (range 0-255)
- **Packed values**: Use `i32` to accommodate NONE (-1)
- **Constants**: Declare with explicit types and use `const` for compile-time evaluation

### Constant Definitions

All constants should be comptime-known values:

```zig
const SHIFT: u5 = 24;  // Not var, must be const
const S0: u21 = 0xAC00;
```

### Map Types

Choose appropriate map types based on value structure:

- `std.AutoHashMap(u21, []u21)` for decomps (CP -> sequence)
- `std.AutoHashMap(u21, std.AutoHashMap(u21, u21))` for recomps (nested)
- `std.AutoHashMap(u21, u8)` for ranks (CP -> byte)

### Stub Implementation

For stub functions, use:
```zig
@panic("TODO: implement")
```

Do NOT return dummy values like `0` or `false` as this can mask bugs.

### Memory Management

The NF struct does NOT own an allocator field. Memory management will be handled by:
- Passing allocators to methods that need allocation
- The binary data being embedded at compile time
- Maps being initialized with allocators passed to init/load functions

## Implementation Strategy

1. Create the file with proper module structure
2. Add standard library imports
3. Define all constants in logical groups
4. Define the NF struct with all fields
5. Add stub helper functions
6. Verify compilation

## Next Steps

After completing this task:
- Task 04 will implement the decoder for reading nf.bin
- Task 05 will implement the RuneSet data structure
- Task 06 will implement NF load methods
- Task 07 will implement decomposition logic
- Task 08 will implement recomposition logic

## Additional Context

### Why Hangul is Special

Unicode contains a large block of precomposed Hangul syllables (U+AC00 to U+D7AF). Rather than storing decomposition data for all 11,172 syllables, the Unicode standard defines an algorithm to compute decompositions. This saves significant memory in the normalization tables.

### Packed Values

The normalization algorithm needs to track both codepoints and their combining classes. Packing them into a single 32-bit value saves memory and simplifies data structures. The upper 8 bits store the combining class (0-255), and the lower 24 bits store the codepoint (sufficient for all Unicode codepoints up to U+10FFFF).

### Exclusion and Quick Check Sets

- **Exclusions**: Codepoints that should NOT be recomposed even if a composition exists (due to Unicode stability requirements)
- **Quick Check**: Codepoints that indicate a string is already in the target normal form, enabling fast validation

These sets enable significant optimization of the normalization algorithm.
