# Task 01: Port util/decoder.go to Zig

## Goal

Port the bit-packed binary decoder from Go to Zig as `src/util/decoder.zig`. This decoder reads compressed binary data using magic number encoding and bit manipulation. It is a foundational utility used to decompress the ENS normalization tables embedded in the library.

## Go Reference Code

Below is the complete `decoder.go` implementation that needs to be ported:

```go
package util

import (
	"fmt"
	"sort"
)

type Decoder struct {
	buf   []byte
	pos   int
	magic []int
	word  byte
	bit   byte
}

func asSigned(i int) int {
	if (i & 1) != 0 {
		return ^i >> 1
	} else {
		return i >> 1
	}
}

func NewDecoder(v []byte) *Decoder {
	var d = &Decoder{}
	d.buf = v
	d.magic = d.readMagic()
	return d
}

func (d *Decoder) AssertEOF() {
	if d.pos < len(d.buf) {
		panic(fmt.Sprintf("expected eof: %d/%d", d.pos, len(d.buf)))
	}
}

func (d *Decoder) readMagic() []int {
	var list []int
	w := 0
	for {
		dw := d.readUnary()
		if dw == 0 {
			break
		}
		w += dw
		list = append(list, w)
	}
	return list
}

func (d *Decoder) readBit() bool {
	if d.bit == 0 {
		d.word = d.buf[d.pos]
		d.pos++
		d.bit = 1
	}
	bit := (d.word & d.bit) != 0
	d.bit <<= 1
	return bit
}

func (d *Decoder) readUnary() int {
	x := 0
	for d.readBit() {
		x++
	}
	return x
}

func (d *Decoder) readBinary(w int) int {
	x := 0
	for b := 1 << (w - 1); b != 0; b >>= 1 {
		if d.readBit() {
			x |= b
		}
	}
	return x
}

func (d *Decoder) ReadUnsigned() int {
	a := 0
	var w int
	for i := 0; ; i++ {
		w = d.magic[i]
		n := 1 << w
		if i+1 == len(d.magic) || !d.readBit() {
			break
		}
		a += n
	}
	return a + d.readBinary(w)
}

func (d *Decoder) readArray(n int, fn func(prev, x int) int) []int {
	v := make([]int, n)
	prev := -1
	for i := 0; i < n; i++ {
		v[i] = fn(prev, d.ReadUnsigned())
		prev = v[i]
	}
	return v
}

func (d *Decoder) ReadSortedAscending(n int) []int {
	return d.readArray(n, func(prev, x int) int { return prev + 1 + x })
}

func (d *Decoder) ReadUnsortedDeltas(n int) []int {
	return d.readArray(n, func(prev, x int) int { return prev + asSigned(x) })
}

func (d *Decoder) ReadString() string {
	v := d.ReadUnsortedDeltas(d.ReadUnsigned())
	cps := make([]rune, len(v))
	for i, x := range v {
		cps[i] = rune(x)
	}
	return string(cps)
}

func (d *Decoder) ReadUnique() []int {
	v := d.ReadSortedAscending(d.ReadUnsigned())
	n := d.ReadUnsigned()
	if n > 0 {
		vX := d.ReadSortedAscending(n)
		vS := d.ReadUnsortedDeltas(n)
		for i := 0; i < n; i++ {
			for x, e := vX[i], vX[i]+vS[i]; x < e; x++ {
				v = append(v, x)
			}
		}
	}
	return v
}

func (d *Decoder) ReadSortedUnique() []int {
	v := d.ReadUnique()
	sort.Ints(v)
	return v
}
```

## Implementation Guidance

### Understanding the Decoder

The `Decoder` is a stateful bit-stream reader that decodes compressed binary data. It uses several encoding techniques:

1. **Bit-Packed Format**: Data is stored at the bit level, not byte level, for maximum compression
2. **Magic Number Encoding**: Uses variable-length encoding based on a "magic" table read from the stream header
3. **Unary Encoding**: Represents numbers as N consecutive 1-bits followed by a 0-bit
4. **Zigzag Encoding**: Encodes signed integers efficiently (0, -1, 1, -2, 2, ...)

### Decoder Struct Fields

```zig
pub const Decoder = struct {
    buf: []const u8,     // The compressed byte buffer to read from
    pos: usize,          // Current byte position in buf
    magic: []const i32,  // Magic numbers for variable-length encoding
    word: u8,            // Current byte being processed bit-by-bit
    bit: u8,             // Current bit mask (1, 2, 4, 8, 16, 32, 64, 128)
};
```

**Field Explanations**:
- `buf`: The input byte slice containing compressed data. Read-only.
- `pos`: Index of the current byte in `buf`. Advances as bytes are consumed.
- `magic`: Array of magic numbers read from the stream header. Used for variable-length integer decoding.
- `word`: The current byte being read bit-by-bit. Loaded from `buf[pos]` when `bit == 0`.
- `bit`: A bitmask that tracks which bit position we're reading (starts at 1, shifts left to 128, then resets).

### Core Methods

#### `readBit() bool`
Reads a single bit from the stream. This is the foundation of all other read operations.

**Logic**:
1. If `bit == 0`, we've exhausted the current byte, so load the next byte from `buf[pos]` into `word` and increment `pos`
2. Set `bit = 1` to start at the least significant bit
3. Check if the current bit is set: `(word & bit) != 0`
4. Shift `bit` left for the next read: `bit <<= 1`
5. Return whether the bit was set

#### `asSigned(i: i32) i32` - Zigzag Decoding
Converts an unsigned integer to a signed integer using zigzag encoding.

**Zigzag Encoding Map**:
- 0 → 0
- 1 → -1
- 2 → 1
- 3 → -2
- 4 → 2

**Logic**:
```zig
if ((i & 1) != 0) {
    return ~i >> 1;  // Odd numbers: negate and shift
} else {
    return i >> 1;   // Even numbers: just shift
}
```

#### `readUnary() i32`
Reads a unary-encoded number. Counts consecutive 1-bits until hitting a 0-bit.

Example: `1110` encodes the number 3 (three 1-bits before the 0-bit).

#### `readBinary(w: i32) i32`
Reads a binary number of `w` bits. Reads from most significant bit to least significant bit.

#### `ReadUnsigned() i32`
Reads a variable-length encoded unsigned integer using the magic table.

**Logic**:
1. Start with accumulator `a = 0`
2. For each magic number at index `i`:
   - Set `w = magic[i]`
   - Calculate `n = 1 << w` (2^w)
   - If we're at the last magic number OR `readBit()` returns false, break
   - Otherwise, add `n` to the accumulator
3. Return `a + readBinary(w)`

This allows encoding small numbers with fewer bits and large numbers with more bits, based on the distribution in the data.

### Array Reading Methods

All array-reading methods allocate memory and require an `Allocator`.

#### `readArray(n: i32, fn: function, allocator: Allocator) []i32`
Generic array reader that reads `n` unsigned integers and applies a function to transform each value based on the previous value.

#### `ReadSortedAscending(n: i32, allocator: Allocator) []i32`
Reads an array of `n` integers stored as ascending deltas. Each value is `prev + 1 + delta`.

Example: To store `[10, 13, 14, 20]`, we store deltas `[10, 2, 0, 5]` (saved as `[10, 2, 0, 5]` since first has no prev).

#### `ReadUnsortedDeltas(n: i32, allocator: Allocator) []i32`
Reads an array of `n` integers stored as signed deltas (using zigzag encoding). Each value is `prev + asSigned(delta)`.

#### `ReadString(allocator: Allocator) []u8`
Reads a string as Unicode codepoints stored using `ReadUnsortedDeltas`. Returns a UTF-8 encoded byte slice.

**Steps**:
1. Read the number of codepoints: `n = ReadUnsigned()`
2. Read codepoint deltas: `codepoints = ReadUnsortedDeltas(n)`
3. Convert codepoints (i32 array) to UTF-8 bytes
4. Return the UTF-8 string

#### `ReadUnique() []i32`
Reads an array of unique integers with an optimized encoding for consecutive runs.

**Format**:
1. Base values: sorted ascending array
2. Number of runs: `n`
3. If `n > 0`:
   - Run start indices: sorted ascending array of length `n`
   - Run lengths: unsorted deltas array of length `n`
   - Expand runs and append to base values

#### `ReadSortedUnique() []i32`
Same as `ReadUnique()` but sorts the result before returning.

### No Allocator Needed for Decoder Initialization

Unlike the array-reading methods, the `Decoder` itself does **NOT** require an allocator for initialization. It works directly on an embedded byte slice.

**Key Points**:
- `init()` should accept `buf: []const u8` and return a `Decoder` value
- The `magic` array will need to be allocated during initialization (use an ArrayList temporarily, then convert to slice)
- All bit-reading state (`pos`, `word`, `bit`) is stored directly in the struct
- The decoder reads from the provided buffer without making copies

### Stubbing Strategy

For this task, you are **NOT implementing the full logic**. Instead:

1. Define the `Decoder` struct with all fields
2. Define all public methods with correct signatures
3. Each method body should be `@panic("TODO: implement {method_name}")`
4. Ensure the file compiles without errors

**Example Stub**:
```zig
pub fn readBit(self: *Decoder) bool {
    @panic("TODO: implement readBit");
}
```

## File Location

Create the file at: **`src/util/decoder.zig`**

The directory `src/util/` should already exist from the Zig project initialization.

## Dependencies

**None**. This is a foundational utility with no dependencies on other project files.

Standard library imports you may need:
```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
```

## Success Criteria

- [ ] File `src/util/decoder.zig` exists
- [ ] `Decoder` struct defined with fields: `buf`, `pos`, `magic`, `word`, `bit`
- [ ] All public methods defined with correct signatures:
  - [ ] `init(buf: []const u8) Decoder` (or similar constructor)
  - [ ] `assertEOF(self: *Decoder) void`
  - [ ] `ReadUnsigned(self: *Decoder) i32`
  - [ ] `ReadSortedAscending(self: *Decoder, n: i32, allocator: Allocator) ![]i32`
  - [ ] `ReadUnsortedDeltas(self: *Decoder, n: i32, allocator: Allocator) ![]i32`
  - [ ] `ReadString(self: *Decoder, allocator: Allocator) ![]u8`
  - [ ] `ReadUnique(self: *Decoder, allocator: Allocator) ![]i32`
  - [ ] `ReadSortedUnique(self: *Decoder, allocator: Allocator) ![]i32`
- [ ] Private/internal methods defined:
  - [ ] `readMagic(self: *Decoder, allocator: Allocator) ![]i32`
  - [ ] `readBit(self: *Decoder) bool`
  - [ ] `readUnary(self: *Decoder) i32`
  - [ ] `readBinary(self: *Decoder, w: i32) i32`
  - [ ] `readArray(self: *Decoder, n: i32, fn: ..., allocator: Allocator) ![]i32`
  - [ ] `asSigned(i: i32) i32` (can be a standalone function)
- [ ] All methods stub with `@panic("TODO: implement")`
- [ ] File compiles without errors

## Validation Commands

After creating the file, verify it compiles:

```bash
zig build
```

**Expected Result**: Build succeeds with no compilation errors. The stubs should compile cleanly even though they will panic at runtime.

## Common Pitfalls

1. **Don't implement logic yet**: Only create stubs. The goal is to establish the API surface, not the implementation.

2. **Bit manipulation types**: Use `u8` for bytes and bit masks. Use `i32` for decoded integers (matching Go's `int` on common platforms).

3. **Error handling**: Methods that allocate (those taking `allocator`) should return `!T` (error union type) since allocation can fail.

4. **Allocator parameter**: Only methods that create arrays need an allocator parameter:
   - `readArray`, `ReadSortedAscending`, `ReadUnsortedDeltas`, `ReadString`, `ReadUnique`, `ReadSortedUnique`
   - The `Decoder` struct itself does NOT store an allocator

5. **Const correctness**: The input buffer should be `[]const u8` since we only read from it.

6. **Magic array ownership**: During `init()`, you'll need to allocate the magic array. Consider storing it in a way that allows the decoder to own it, or require the caller to manage its lifetime.

7. **Method receivers**: In Zig, methods take `self: *Decoder` or `self: *const Decoder`. Use `*Decoder` for methods that mutate state (most of them), and `*const Decoder` for read-only methods (there aren't many).

8. **Function types**: For `readArray`, you'll need to define a function pointer type or use `anytype` for the callback parameter.

## Notes for Implementer

- The Go code uses dynamic slicing with `append`. In Zig, you'll use `ArrayList` for dynamic arrays.
- Go's `panic` with formatted strings becomes Zig's `@panic` with string literals. For `assertEOF`, you might want to use `std.debug.print` before panicking or create a custom error.
- Go's `rune` is equivalent to Zig's `i32` (Unicode codepoint).
- UTF-8 encoding in Zig uses `std.unicode.utf8Encode`.
- For sorting, use `std.sort.sort` with a comparison function.

## Next Steps

After this task is complete with stubs:
1. Task 02 will implement the decoder logic step-by-step
2. Task 03 will add tests for the decoder
3. Later tasks will use this decoder to decompress normalization tables
