# Task 09: Implement NF Initialization

## Goal

Port the NF constructor from Go to Zig as an `init()` method. This loads and decodes the embedded `nf.bin` binary data to populate all normalization tables required for Unicode NFC normalization.

## Overview

The NF initialization is the core bootstrap process that loads compressed normalization data from the embedded `nf.bin` file. It uses the Decoder to read various encodings (strings, unique values, sorted ascending, unsorted deltas) and builds the data structures needed for decomposition and recomposition of Unicode text.

The binary format encodes:
1. **Unicode version string**: The Unicode standard version (e.g., "15.0.0")
2. **Exclusions set**: Codepoints excluded from composition
3. **QuickCheck set**: Codepoints for fast normalization validation
4. **Decomposition tables**: Maps codepoints to their decomposed forms (1-char and 2-char)
5. **Recomposition tables**: Inverse of decomposition (excluding exclusions)
6. **Ranks table**: Canonical combining class values for reordering

## Go Reference Code

From `/Users/williamcory/z-ens-normalize/go-ens-normalize/nf/nf.go` lines 53-96:

```go
func New() *NF {
	d := util.NewDecoder(compressed)
	self := NF{}
	self.unicodeVersion = d.ReadString()
	self.exclusions = util.NewRuneSetFromInts(d.ReadUnique())
	self.quickCheck = util.NewRuneSetFromInts(d.ReadUnique())
	self.decomps = make(map[rune][]rune)
	self.recomps = make(map[rune]map[rune]rune)
	self.ranks = make(map[rune]byte)

	decomp1 := d.ReadSortedUnique()
	decomp1A := d.ReadUnsortedDeltas(len(decomp1))
	for i, cp := range decomp1 {
		self.decomps[rune(cp)] = []rune{rune(decomp1A[i])}
	}
	decomp2 := d.ReadSortedUnique()
	decomp2A := d.ReadUnsortedDeltas(len(decomp2))
	decomp2B := d.ReadUnsortedDeltas(len(decomp2))
	for i, cp := range decomp2 {
		cp := rune(cp)
		cpA := rune(decomp2A[i])
		cpB := rune(decomp2B[i])
		self.decomps[cp] = []rune{cpB, cpA}
		if !self.exclusions.Contains((cp)) {
			recomp := self.recomps[cpA]
			if recomp == nil {
				recomp = make(map[rune]rune)
				self.recomps[cpA] = recomp
			}
			recomp[cpB] = cp
		}
	}
	for i := 1; ; i++ {
		v := d.ReadUnique()
		if len(v) == 0 {
			break
		}
		for _, cp := range v {
			self.ranks[rune(cp)] = byte(i)
		}
	}
	d.AssertEOF()
	return &self
}
```

## Implementation Guidance

### Understanding the nf.bin Format

The binary file is structured as a sequence of encoded data sections:

1. **Unicode Version** (ReadString): Version string encoded as UTF-8
2. **Exclusions** (ReadUnique): Codepoints that cannot be recomposed
3. **QuickCheck** (ReadUnique): Codepoints indicating normalized text
4. **Decomp1 Data** (1-character decompositions):
   - `decomp1` (ReadSortedUnique): Codepoints that decompose to 1 character
   - `decomp1A` (ReadUnsortedDeltas): The single decomposition target for each
5. **Decomp2 Data** (2-character decompositions):
   - `decomp2` (ReadSortedUnique): Codepoints that decompose to 2 characters
   - `decomp2A` (ReadUnsortedDeltas): First character of decomposition
   - `decomp2B` (ReadUnsortedDeltas): Second character of decomposition
6. **Ranks Data** (infinite loop until empty):
   - Repeated calls to ReadUnique(), each returning codepoints with combining class `i`
   - Loop breaks when ReadUnique() returns empty array

### Embedding the Binary File

Use Zig's `@embedFile` to include the binary data at compile time:

```zig
const compressed = @embedFile("nf.bin");
```

**Important**: The path is relative to the source file. Since `nf.zig` is at `src/nf/nf.zig` and `nf.bin` should be at `src/nf/nf.bin`, use:

```zig
const compressed = @embedFile("nf.bin");
```

### Decoder Initialization

Create a decoder from the embedded bytes:

```zig
var decoder = Decoder.init(compressed);
```

Note: `Decoder.init()` does NOT require an allocator - it reads directly from the embedded bytes. However, methods like `ReadString()`, `ReadUnique()`, etc. DO require an allocator for their return values.

### Building the decomps Map

The decomposition table is built in two phases:

**Phase 1: 1-Character Decompositions**
```zig
// Read codepoints that decompose to 1 character
const decomp1 = try decoder.ReadSortedUnique(allocator);
// Read their single decomposition targets
const decomp1A = try decoder.ReadUnsortedDeltas(decomp1.len, allocator);
// Populate decomps map
for (decomp1, decomp1A) |cp, target| {
    const decomp = try allocator.alloc(u21, 1);
    decomp[0] = @intCast(target);
    try self.decomps.put(@intCast(cp), decomp);
}
```

**Phase 2: 2-Character Decompositions**
```zig
// Read codepoints that decompose to 2 characters
const decomp2 = try decoder.ReadSortedUnique(allocator);
// Read first character of decomposition
const decomp2A = try decoder.ReadUnsortedDeltas(decomp2.len, allocator);
// Read second character of decomposition
const decomp2B = try decoder.ReadUnsortedDeltas(decomp2.len, allocator);
// Populate decomps map
for (decomp2, decomp2A, decomp2B) |cp, targetA, targetB| {
    const decomp = try allocator.alloc(u21, 2);
    decomp[0] = @intCast(targetB);  // Note: B comes first!
    decomp[1] = @intCast(targetA);
    try self.decomps.put(@intCast(cp), decomp);
}
```

**Important**: The decomposition stores `[cpB, cpA]` not `[cpA, cpB]`. This matches the Go code.

### Building the recomps Map

The recomposition table is the inverse of the 2-character decomposition table, excluding exclusions:

```zig
// Continuing from Phase 2 loop:
for (decomp2, decomp2A, decomp2B) |cp, targetA, targetB| {
    const cp_u21: u21 = @intCast(cp);
    const cpA_u21: u21 = @intCast(targetA);
    const cpB_u21: u21 = @intCast(targetB);

    // Only add to recomps if not excluded
    if (!self.exclusions.contains(cp_u21)) {
        // Get or create inner map for cpA
        var inner = self.recomps.get(cpA_u21);
        if (inner == null) {
            var new_inner = std.AutoHashMap(u21, u21).init(allocator);
            try self.recomps.put(cpA_u21, new_inner);
            inner = self.recomps.get(cpA_u21);
        }
        // Map cpB -> cp
        try inner.?.put(cpB_u21, cp_u21);
    }
}
```

This creates a nested map structure: `recomps[first_char][second_char] = composed_char`

### Building the ranks Map

The ranks table maps codepoints to their canonical combining class values:

```zig
var rank_value: u8 = 1;
while (true) : (rank_value += 1) {
    const cps = try decoder.ReadUnique(allocator);
    if (cps.len == 0) break;

    for (cps) |cp| {
        try self.ranks.put(@intCast(cp), rank_value);
    }
}
```

The combining class values start at 1 (not 0) and increment with each batch. An empty array signals the end of ranks data.

### Method Signature

```zig
pub fn init(allocator: std.mem.Allocator) !NF {
    const compressed = @embedFile("nf.bin");
    var decoder = Decoder.init(compressed);

    var self = NF{
        .unicodeVersion = undefined,
        .exclusions = undefined,
        .quickCheck = undefined,
        .decomps = std.AutoHashMap(u21, []u21).init(allocator),
        .recomps = std.AutoHashMap(u21, std.AutoHashMap(u21, u21)).init(allocator),
        .ranks = std.AutoHashMap(u21, u8).init(allocator),
    };

    // Load data...

    try decoder.assertEOF();
    return self;
}
```

### Stubbing Strategy

For this task, you should create the full structure but stub the actual implementation:

1. Define the `init()` method signature
2. Embed the nf.bin file with `@embedFile`
3. Initialize the decoder
4. Add all the ReadString/ReadUnique/etc calls with `@panic("TODO: implement")`
5. Include the loop structures (for decomps, recomps, ranks)
6. Call `assertEOF()` at the end
7. Return the initialized struct

**Example Stub**:
```zig
pub fn init(allocator: std.mem.Allocator) !NF {
    @panic("TODO: implement init()");
}
```

OR for a more detailed stub, you can outline the structure:

```zig
pub fn init(allocator: std.mem.Allocator) !NF {
    const compressed = @embedFile("nf.bin");
    var decoder = Decoder.init(compressed);

    var self = NF{
        .unicodeVersion = undefined,
        .exclusions = undefined,
        .quickCheck = undefined,
        .decomps = std.AutoHashMap(u21, []u21).init(allocator),
        .recomps = std.AutoHashMap(u21, std.AutoHashMap(u21, u21)).init(allocator),
        .ranks = std.AutoHashMap(u21, u8).init(allocator),
    };

    // TODO: Read unicode version
    // self.unicodeVersion = try decoder.ReadString(allocator);

    // TODO: Read exclusions set
    // self.exclusions = RuneSet.fromInts(allocator, try decoder.ReadUnique(allocator));

    // TODO: Read quickCheck set
    // self.quickCheck = RuneSet.fromInts(allocator, try decoder.ReadUnique(allocator));

    // TODO: Read decomp1 data and populate decomps map

    // TODO: Read decomp2 data and populate decomps + recomps maps

    // TODO: Read ranks data in loop

    try decoder.assertEOF();
    return self;
}
```

## File Location

Add the `init()` method to: `/Users/williamcory/z-ens-normalize/src/nf/nf.zig`

This file should already exist from Task 03 with the NF struct definition.

## Dependencies

This task depends on:

1. **Task 01**: `src/util/decoder.zig` - Decoder type and all read methods
2. **Task 02**: `src/util/runeset.zig` - RuneSet type and fromInts() factory
3. **Task 03**: `src/nf/nf.zig` - NF struct definition with all fields
4. **Task 04**: `src/nf/nf.bin` - Embedded binary data file

Import structure:
```zig
const std = @import("std");
const Decoder = @import("../util/decoder.zig").Decoder;
const RuneSet = @import("../util/runeset.zig").RuneSet;
const Allocator = std.mem.Allocator;
```

## Success Criteria

- [ ] `init()` method signature defined: `pub fn init(allocator: std.mem.Allocator) !NF`
- [ ] `@embedFile("nf.bin")` declared and assigned to a const
- [ ] Decoder initialization code present: `var decoder = Decoder.init(compressed);`
- [ ] Unicode version read call present: `decoder.ReadString()`
- [ ] Exclusions set read call present: `RuneSet.fromInts()` with `decoder.ReadUnique()`
- [ ] QuickCheck set read call present: `RuneSet.fromInts()` with `decoder.ReadUnique()`
- [ ] Decomp1 reading logic present: `ReadSortedUnique()` + `ReadUnsortedDeltas()`
- [ ] Decomp1 map population loop present
- [ ] Decomp2 reading logic present: `ReadSortedUnique()` + 2x `ReadUnsortedDeltas()`
- [ ] Decomp2 map population loop present
- [ ] Recomps map building logic present (in decomp2 loop, checking exclusions)
- [ ] Ranks reading loop present: infinite loop with `ReadUnique()`, breaks on empty
- [ ] Ranks map population present
- [ ] `assertEOF()` call at end
- [ ] Returns initialized NF struct
- [ ] File compiles without errors
- [ ] `zig build` succeeds

## Validation Commands

After implementation, verify the code compiles:

```bash
zig build
```

This should succeed without compilation errors (warnings about stubbed code are acceptable).

## Common Pitfalls

### 1. Decoder Initialization vs Method Calls

- `Decoder.init()` does NOT take an allocator (reads embedded bytes)
- `decoder.ReadString()`, `ReadUnique()`, etc. DO take allocators (allocate return values)

### 2. Map Initialization

Maps in the NF struct need to be initialized empty, then populated:

```zig
.decomps = std.AutoHashMap(u21, []u21).init(allocator),
```

NOT:
```zig
.decomps = undefined,  // Wrong - map needs init()
```

### 3. Decomposition Order

The 2-character decomposition stores `[cpB, cpA]` not `[cpA, cpB]`. The Go code does:

```go
self.decomps[cp] = []rune{cpB, cpA}  // B first, then A!
```

### 4. Recomps Nested Maps

The recomps structure is a nested map. You need to:
1. Check if outer map has entry for cpA
2. Create inner map if needed
3. Insert into inner map

### 5. Ranks Loop

The ranks loop is infinite with a break condition:

```zig
var i: u8 = 1;
while (true) : (i += 1) {
    const v = try decoder.ReadUnique(allocator);
    if (v.len == 0) break;  // Exit on empty array
    // ... populate ranks
}
```

NOT a for loop - you don't know the count in advance.

### 6. Exclusions Check

When building recomps, check exclusions:

```zig
if (!self.exclusions.contains(cp)) {
    // Add to recomps
}
```

NOT:
```zig
if (self.exclusions.contains(cp)) {  // Wrong - double negative
    // Add to recomps
}
```

### 7. embedFile Path

The path is relative to the source file:
- `src/nf/nf.zig` → `@embedFile("nf.bin")` looks for `src/nf/nf.bin`

NOT:
```zig
@embedFile("src/nf/nf.bin")  // Wrong - too many directories
@embedFile("../nf.bin")      // Wrong - going up then back
```

### 8. Type Conversions

Decoder methods return `[]i32`, but maps use `u21`:

```zig
const values = try decoder.ReadSortedUnique(allocator);  // []i32
for (values) |val| {
    const cp: u21 = @intCast(val);  // Convert to u21
    // ... use cp
}
```

### 9. Memory Management

All allocated slices (from decoder reads, decomp arrays) are owned by the NF struct. They should be freed when NF is deinitialized (future task).

### 10. AssertEOF Placement

Call `assertEOF()` after all reads, before returning:

```zig
try decoder.assertEOF();
return self;
```

This validates that we've consumed all binary data correctly.

## Implementation Strategy

1. Add the necessary imports at the top of `nf.zig`
2. Add the `@embedFile("nf.bin")` declaration
3. Define the `init()` method with full signature
4. Create the decoder from embedded bytes
5. Initialize the NF struct with empty maps
6. Add unicode version read (stub)
7. Add exclusions set read (stub)
8. Add quickCheck set read (stub)
9. Add decomp1 section with read calls and loop structure (stub)
10. Add decomp2 section with read calls and loop structure (stub)
11. Add recomps building logic in decomp2 loop (stub)
12. Add ranks loop with read calls and population logic (stub)
13. Add assertEOF() call
14. Return the initialized struct
15. Verify compilation

## Additional Context

### Why Two Decomposition Phases?

Unicode decompositions are either 1 or 2 characters (3+ are recursive). Storing them separately:
- Saves space (1-char decomps don't need 2-element arrays)
- Enables type-specific compression in the binary format
- Matches Unicode normalization algorithm structure

### Recomposition as Inverse

The recomposition table is the mathematical inverse of the 2-character decomposition table:
- Decomp: `cp → [cpB, cpA]`
- Recomp: `(cpA, cpB) → cp`

This allows efficient composition during normalization.

### Exclusions Purpose

Some codepoints have decompositions but should NOT be recomposed (Unicode stability requirement). The exclusions set prevents composition of these codepoints.

### Ranks and Canonical Ordering

The ranks table stores canonical combining class (CCC) values. During normalization, combining marks must be reordered by their CCC values before composition. This ensures canonical equivalence.

### Binary Format Efficiency

The binary format uses multiple compression techniques:
- Variable-length encoding (magic numbers)
- Delta encoding (sorted ascending, unsorted deltas)
- Run-length encoding (ReadUnique with ranges)
- Bit-packing (Decoder reads at bit-level)

This compresses Unicode normalization data from ~50KB to ~15KB.

## Next Steps

After completing this task:
1. Task 10 will implement the actual decoder methods (currently stubbed)
2. Task 11 will implement RuneSet methods (fromInts, contains)
3. Task 12 will test the NF initialization with sample data
4. Task 13 will implement decomposition logic using these tables
5. Task 14 will implement recomposition logic using these tables

## Testing Hints

Once implemented, you can validate initialization by:

1. Checking the Unicode version string (should be "15.0.0" or similar)
2. Checking map sizes (decomps should have ~1000 entries, recomps ~500, ranks ~200)
3. Checking specific values (e.g., 'é' (U+00E9) decomposes to ['e', '◌́'] (U+0065, U+0301))
4. Ensuring assertEOF() doesn't panic (all data consumed)

These tests will come in later tasks once the decoder is fully implemented.
