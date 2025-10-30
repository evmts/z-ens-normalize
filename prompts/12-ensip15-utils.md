# Task 12: Implement ENSIP15 Utility Functions

## Goal

Port utility functions for string manipulation, formatting, and helper operations to `src/ensip15/utils.zig`. These functions provide common operations for splitting/joining domain labels, formatting codepoints for display, and manipulating rune slices.

## Context

The ENSIP15 implementation requires various utility functions for:
- **Label Operations**: Splitting ENS names by dots and joining labels
- **Display Formatting**: Converting codepoints to safe, readable representations
- **String Operations**: Checking ASCII status, deduplicating runes, comparing rune slices
- **Token Operations**: Flattening output tokens into codepoint arrays

These utilities are used throughout the normalization and validation process. They handle the conversion between different representations (UTF-8 strings, rune arrays, hex sequences) and provide safe formatting for error messages and debugging.

## Go Reference Code

### Complete utils.go File

From `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/utils.go`:

```go
package ensip15

import (
	"fmt"
	"strings"
)

func Join(labels []string) string {
	return strings.Join(labels, ".")
}

func Split(name string) []string {
	if len(name) == 0 {
		return nil // empty name allowance
	}
	return strings.Split(name, ".")
}

func ToHexSequence(cps []rune) string {
	var sb strings.Builder
	for i, cp := range cps {
		if i > 0 {
			sb.WriteRune(' ')
		}
		appendHex(&sb, cp)
	}
	return sb.String()
}

func appendHex(sb *strings.Builder, cp rune) {
	sb.WriteString(fmt.Sprintf("%02X", cp))
}

func appendHexEscape(sb *strings.Builder, cp rune) {
	sb.WriteRune('{')
	appendHex(sb, cp)
	sb.WriteRune('}')
}

func isASCII(cps []rune) bool {
	for _, cp := range cps {
		if cp >= 0x80 {
			return false
		}
	}
	return true
}

func uniqueRunes(cps []rune) []rune {
	set := make(map[rune]bool)
	v := make([]rune, 0, len(cps))
	for _, cp := range cps {
		if !set[cp] {
			set[cp] = true
			v = append(v, cp)
		}
	}
	return v
}

func compareRunes(a, b []rune) int {
	c := len(a) - len(b)
	if c != 0 {
		return c
	}
	for i, aa := range a {
		switch {
		case aa < b[i]:
			return -1
		case aa > b[i]:
			return 1
		}
	}
	return 0
}

func (l *ENSIP15) SafeCodepoint(cp rune) string {
	var sb strings.Builder
	if !l.shouldEscape.Contains(cp) {
		sb.WriteRune('"')
		l.safeImplode(&sb, []rune{cp})
		sb.WriteRune('"')
		sb.WriteRune(' ')
	}
	appendHexEscape(&sb, cp)
	return sb.String()
}

func (l *ENSIP15) safeImplode(sb *strings.Builder, cps []rune) {
	if len(cps) == 0 {
		return
	}
	if l.combiningMarks.Contains(cps[0]) {
		sb.WriteRune(0x25CC)
	}
	for _, cp := range cps {
		if l.shouldEscape.Contains(cp) {
			appendHexEscape(sb, cp)
		} else {
			sb.WriteRune(cp)
		}
	}
	// some messages can be mixed-directional and result in spillover
	// use 200E after a input string to reset the bidi direction
	// https://www.w3.org/International/questions/qa-bidi-unicode-controls#exceptions
	sb.WriteRune(0x200E)
}

func (l *ENSIP15) SafeImplode(cps []rune) string {
	var sb strings.Builder
	l.safeImplode(&sb, cps)
	return sb.String()
}
```

### FlattenTokens Function

From `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/output.go`:

```go
func FlattenTokens(tokens []OutputToken) []rune {
	n := 0
	for _, x := range tokens {
		n += len(x.Codepoints)
	}
	cps := make([]rune, 0, n)
	for _, x := range tokens {
		cps = append(cps, x.Codepoints...)
	}
	return cps
}
```

## Functions to Port

### 1. split() - Split ENS Name by Dots

**Go Signature:**
```go
func Split(name string) []string
```

**Zig Signature:**
```zig
pub fn split(allocator: Allocator, name: []const u8) ![][]const u8
```

**Behavior:**
- Splits UTF-8 string by '.' (U+002E) separator
- Returns empty slice for empty input string
- Each returned slice points into original name (no copying)
- Allocates only the slice container, not individual labels

### 2. join() - Join Labels with Dots

**Go Signature:**
```go
func Join(labels []string) string
```

**Zig Signature:**
```zig
pub fn join(allocator: Allocator, labels: []const []const u8) ![]u8
```

**Behavior:**
- Joins label slices with '.' separator
- Allocates new string for result
- Returns owned slice that caller must free

### 3. toHexSequence() - Format as Hex Sequence

**Go Signature:**
```go
func ToHexSequence(cps []rune) string
```

**Zig Signature:**
```zig
pub fn toHexSequence(allocator: Allocator, cps: []const u21) ![]u8
```

**Behavior:**
- Formats codepoints as space-separated hex values
- Uses uppercase hex (e.g., "41 42 43" for "ABC")
- Minimum 2 digits per codepoint (uses %02X format)
- Example: `[0x61, 0x62]` → `"61 62"`

### 4. safeCodepoint() - Format Single Codepoint Safely

**Go Signature:**
```go
func (l *ENSIP15) SafeCodepoint(cp rune) string
```

**Zig Signature:**
```zig
pub fn safeCodepoint(self: *const ENSIP15, allocator: Allocator, cp: u21) ![]u8
```

**Behavior:**
- If codepoint should NOT be escaped: shows `"char" {HEX}`
- If codepoint should be escaped: shows `{HEX}` only
- Uses shouldEscape RuneSet to determine escaping
- Wraps single codepoint in quotes if safe to display

### 5. safeImplode() - Format Codepoint Array Safely

**Go Signature:**
```go
func (l *ENSIP15) SafeImplode(cps []rune) string
```

**Zig Signature:**
```zig
pub fn safeImplode(self: *const ENSIP15, allocator: Allocator, cps: []const u21) ![]u8
```

**Behavior:**
- Formats codepoint array as readable string
- Prefixes with U+25CC (◌) if first codepoint is combining mark
- Escapes codepoints in shouldEscape set as `{HEX}`
- Appends U+200E (left-to-right mark) to reset bidi direction
- Used for error messages and debugging output

### 6. isAscii() - Check if All ASCII

**Go Signature:**
```go
func isASCII(cps []rune) bool
```

**Zig Signature:**
```zig
pub fn isAscii(cps: []const u21) bool
```

**Behavior:**
- Returns true if all codepoints are < 0x80
- Returns true for empty slice
- No allocation needed

### 7. uniqueRunes() - Deduplicate Runes

**Go Signature:**
```go
func uniqueRunes(cps []rune) []rune
```

**Zig Signature:**
```zig
pub fn uniqueRunes(allocator: Allocator, cps: []const u21) ![]u21
```

**Behavior:**
- Returns array with duplicates removed
- Preserves first occurrence order
- Uses hash set for O(n) performance
- Allocates result array

### 8. compareRunes() - Compare Rune Slices

**Go Signature:**
```go
func compareRunes(a, b []rune) int
```

**Zig Signature:**
```zig
pub fn compareRunes(a: []const u21, b: []const u21) i32
```

**Behavior:**
- First compares by length: returns `len(a) - len(b)` if different
- Then lexicographically compares elements
- Returns: -1 if a < b, 0 if equal, 1 if a > b
- Used for sorting and ordering

### 9. flattenTokens() - Flatten Token Array

**Go Signature:**
```go
func FlattenTokens(tokens []OutputToken) []rune
```

**Zig Signature:**
```zig
pub fn flattenTokens(allocator: Allocator, tokens: []const OutputToken) ![]u21
```

**Behavior:**
- Extracts all codepoints from OutputToken array
- Concatenates codepoints field from each token
- Pre-calculates total length for single allocation
- Returns flattened codepoint array

## Implementation Guidance

### Type Mapping Patterns

**Go to Zig type mappings:**
- `string` → `[]const u8` (UTF-8 encoded)
- `[]string` → `[]const []const u8` or `[][]const u8`
- `[]rune` → `[]const u21` (Unicode codepoints)
- `rune` → `u21` (Unicode codepoint)
- `int` → `i32` (for comparison results)
- `bool` → `bool`
- `strings.Builder` → `std.ArrayList(u8)` for building strings

### Allocation Patterns

**Functions requiring allocator:**
- `split()` - allocates slice of slices
- `join()` - allocates result string
- `toHexSequence()` - allocates formatted string
- `safeCodepoint()` - allocates formatted string
- `safeImplode()` - allocates formatted string
- `uniqueRunes()` - allocates deduplicated array
- `flattenTokens()` - allocates flattened array

**Functions NOT requiring allocator:**
- `isAscii()` - pure predicate
- `compareRunes()` - pure comparison

### Key Design Principles

1. **UTF-8 vs Runes**: Distinguish between UTF-8 byte strings (`[]const u8`) and codepoint arrays (`[]const u21`)
2. **Memory Management**: Functions that allocate return owned slices; caller must free
3. **Const Correctness**: Use `[]const` for read-only input parameters
4. **Error Handling**: Return `!T` for functions that can fail (allocation errors)
5. **Stub Implementation**: All functions should be stubbed with appropriate signatures

### File Structure

Create the file with this organization:

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const ENSIP15 = @import("types.zig").ENSIP15;
const OutputToken = @import("types.zig").OutputToken;

// === Label Operations ===

/// Split ENS name by '.' separator into labels
/// Returns slice of slices pointing into original name (caller must free outer slice)
pub fn split(allocator: Allocator, name: []const u8) ![][]const u8 {
    _ = allocator;
    _ = name;
    @panic("TODO: implement split");
}

/// Join labels with '.' separator
/// Returns owned string (caller must free)
pub fn join(allocator: Allocator, labels: []const []const u8) ![]u8 {
    _ = allocator;
    _ = labels;
    @panic("TODO: implement join");
}

// === Formatting Functions ===

/// Format codepoints as space-separated uppercase hex (e.g., "41 42 43")
pub fn toHexSequence(allocator: Allocator, cps: []const u21) ![]u8 {
    _ = allocator;
    _ = cps;
    @panic("TODO: implement toHexSequence");
}

/// Format single codepoint safely for display
/// Returns: "char" {HEX} or {HEX} depending on shouldEscape
pub fn safeCodepoint(self: *const ENSIP15, allocator: Allocator, cp: u21) ![]u8 {
    _ = self;
    _ = allocator;
    _ = cp;
    @panic("TODO: implement safeCodepoint");
}

/// Format codepoint array safely for display
/// Handles combining marks, escaping, and bidi reset
pub fn safeImplode(self: *const ENSIP15, allocator: Allocator, cps: []const u21) ![]u8 {
    _ = self;
    _ = allocator;
    _ = cps;
    @panic("TODO: implement safeImplode");
}

// === Rune Operations ===

/// Check if all codepoints are ASCII (< 0x80)
pub fn isAscii(cps: []const u21) bool {
    _ = cps;
    @panic("TODO: implement isAscii");
}

/// Remove duplicate codepoints, preserving first occurrence order
pub fn uniqueRunes(allocator: Allocator, cps: []const u21) ![]u21 {
    _ = allocator;
    _ = cps;
    @panic("TODO: implement uniqueRunes");
}

/// Compare two codepoint slices lexicographically
/// Returns: negative if a < b, 0 if equal, positive if a > b
pub fn compareRunes(a: []const u21, b: []const u21) i32 {
    _ = a;
    _ = b;
    @panic("TODO: implement compareRunes");
}

// === Token Operations ===

/// Flatten OutputToken array into single codepoint array
pub fn flattenTokens(allocator: Allocator, tokens: []const OutputToken) ![]u21 {
    _ = allocator;
    _ = tokens;
    @panic("TODO: implement flattenTokens");
}

// === Internal Helpers ===

/// Helper: append single codepoint as hex to ArrayList
fn appendHex(list: *std.ArrayList(u8), cp: u21) !void {
    _ = list;
    _ = cp;
    @panic("TODO: implement appendHex");
}

/// Helper: append codepoint in {HEX} format to ArrayList
fn appendHexEscape(list: *std.ArrayList(u8), cp: u21) !void {
    _ = list;
    _ = cp;
    @panic("TODO: implement appendHexEscape");
}
```

### Important Notes

1. **Dot Separator**: Use `'.'` (0x002E) as the label separator
2. **Hex Format**: Use uppercase hex with minimum 2 digits (pad with leading zero)
3. **Split Returns**: Split returns slices pointing into original - no string copying
4. **Bidi Reset**: SafeImplode appends U+200E to reset bidirectional text direction
5. **Combining Mark**: SafeImplode prepends U+25CC (◌) if first char is combining mark
6. **Compare Return**: compareRunes returns i32 for difference values (can be > 1)
7. **ASCII Check**: ASCII is defined as codepoints < 0x80 (not < 0x7F)

## File Location

Create: `src/ensip15/utils.zig`

## Dependencies

- Task 06: `OutputToken` type defined in `src/ensip15/types.zig`
- Task 06: `ENSIP15` type defined in `src/ensip15/types.zig`
- Standard library: `std.mem.Allocator`, `std.ArrayList`, `std.AutoHashMap`

## Success Criteria

- [ ] File `src/ensip15/utils.zig` created
- [ ] `split()` function defined: `pub fn split(allocator: Allocator, name: []const u8) ![][]const u8`
- [ ] `join()` function defined: `pub fn join(allocator: Allocator, labels: []const []const u8) ![]u8`
- [ ] `toHexSequence()` function defined: `pub fn toHexSequence(allocator: Allocator, cps: []const u21) ![]u8`
- [ ] `safeCodepoint()` method defined: takes `*const ENSIP15` receiver
- [ ] `safeImplode()` method defined: takes `*const ENSIP15` receiver
- [ ] `isAscii()` function defined: returns `bool`, no allocator
- [ ] `uniqueRunes()` function defined: removes duplicates
- [ ] `compareRunes()` function defined: returns `i32`, no allocator
- [ ] `flattenTokens()` function defined: takes `[]const OutputToken` parameter
- [ ] Helper functions `appendHex()` and `appendHexEscape()` defined
- [ ] All functions stubbed with `@panic("TODO")` or similar
- [ ] All imports correct (types.zig, std)
- [ ] File compiles without errors
- [ ] `zig build` succeeds

## Validation Commands

```bash
# Verify file compiles
zig build

# Check for compilation errors in utils.zig specifically
zig build-exe src/ensip15/utils.zig --dep types --mod types::src/ensip15/types.zig --mod std::std -femit-bin=/dev/null
```

## Common Pitfalls

1. **Split Ownership**: Split returns slices INTO original name, not copies - only allocate outer slice
2. **Join Allocation**: Join must allocate new string with separators included
3. **Hex Format**: Use `%02X` equivalent - uppercase, minimum 2 digits
4. **ASCII Boundary**: ASCII is < 0x80, not < 0x7F (includes DEL)
5. **Compare Length**: compareRunes first checks length difference before element comparison
6. **ArrayList vs String**: Use `std.ArrayList(u8)` for building strings, return `[]u8`
7. **ENSIP15 Receiver**: safeCodepoint and safeImplode need `self: *const ENSIP15` parameter
8. **Token Flattening**: Pre-calculate total length for efficient single allocation
9. **Const Slices**: Input parameters should be `[]const u21` or `[]const u8`
10. **Error Return**: Functions with allocator return `!T` for potential allocation failure

## Next Steps

After completing this task:
- Task 13 will implement ENSIP15 validation logic
- Task 14 will implement ENSIP15 normalization logic
- Task 15 will implement ENSIP15 beautification logic
- These utilities will be used extensively by normalization functions

## Notes

- This is a stub implementation task - signatures and structure only
- Focus on getting type signatures correct
- All functions should panic with descriptive messages
- The formatters (safe*) are used heavily in error messages
- Split/join are fundamental for handling ENS domain labels
- Comparison and uniqueness functions used in validation logic
