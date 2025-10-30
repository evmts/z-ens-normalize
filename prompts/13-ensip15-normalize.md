# Task 13: Implement ENSIP15 normalize() Method

## Goal

Port the main normalization pipeline from Go to Zig. This is the core public API that takes a name and returns its normalized form according to ENSIP15 specification.

The `normalize()` method orchestrates the entire normalization process: splitting the name into labels, tokenizing, applying NFC normalization, validating against multiple rules, and reassembling into the final normalized form.

This task focuses on creating the method signatures and structure. Most validation logic will stub with `unreachable` for now, to be implemented in subsequent tasks.

## Go Reference Code

Below are the key functions from the Go implementation that need to be ported:

### Normalize() - Main Entry Point (lines 142-156)

```go
func (l *ENSIP15) Normalize(name string) (string, error) {
	return l.transform(
		name,
		l.nf.NFC,
		func(e EmojiSequence) []rune { return e.normalized },
		func(tokens []OutputToken) (string, error) {
			cps := FlattenTokens(tokens)
			_, err := l.checkValidLabel(cps, tokens)
			if err != nil {
				return "", err
			}
			return string(cps), nil
		},
	)
}
```

### transform() - Normalization Pipeline (lines 197-221)

```go
func (l *ENSIP15) transform(
	name string,
	nf func([]rune) []rune,
	ef func(EmojiSequence) []rune,
	normalizer func(tokens []OutputToken) (string, error),
) (string, error) {
	labels := Split(name)
	for i, label := range labels {
		cps := []rune(label)
		tokens, err := l.outputTokenize(cps, nf, ef)
		if err == nil {
			var norm string
			norm, err = normalizer(tokens)
			if err == nil {
				labels[i] = norm
				continue
			}
		}
		if len(labels) > 0 {
			err = fmt.Errorf("invalid label \"%s\": %w", l.SafeImplode(cps), err)
		}
		return "", err
	}
	return Join(labels), nil
}
```

### checkLeadingUnderscore() - Underscore Validation (lines 223-238)

```go
func checkLeadingUnderscore(cps []rune) error {
	const UNDERSCORE = 0x5F
	allowed := true
	for _, cp := range cps {
		if allowed {
			if cp != UNDERSCORE {
				allowed = false
			}
		} else {
			if cp == UNDERSCORE {
				return ErrLeadingUnderscore
			}
		}
	}
	return nil
}
```

### checkLabelExtension() - Hyphen Validation (lines 240-246)

```go
func checkLabelExtension(cps []rune) error {
	const HYPHEN = 0x2D
	if len(cps) >= 4 && cps[2] == HYPHEN && cps[3] == HYPHEN {
		return fmt.Errorf("%w: %s", ErrInvalidLabelExtension, string(cps[:4]))
	}
	return nil
}
```

### checkCombiningMarks() - Combining Mark Validation (lines 248-262)

```go
func (l *ENSIP15) checkCombiningMarks(tokens []OutputToken) error {
	for i, x := range tokens {
		if x.Emoji == nil {
			cp := x.Codepoints[0]
			if l.combiningMarks.Contains(cp) {
				if i == 0 {
					return fmt.Errorf("%v: %s", ErrCMLeading, l.SafeCodepoint(cp))
				} else {
					return fmt.Errorf("%v: %s + %s", ErrCMAfterEmoji, tokens[i-1].Emoji.Beautified(), l.SafeCodepoint(cp))
				}
			}
		}
	}
	return nil
}
```

### checkFenced() - Fenced Character Validation (lines 264-286)

```go
func (l *ENSIP15) checkFenced(cps []rune) error {
	name, ok := l.fenced[cps[0]]
	if ok {
		return fmt.Errorf("%w: %s", ErrFencedLeading, name)
	}
	n := len(cps)
	lastPos := -1
	var lastName string
	for i := 1; i < n; i++ {
		name, ok := l.fenced[cps[i]]
		if ok {
			if lastPos == i {
				return fmt.Errorf("%w: %s + %s", ErrFencedAdjacent, lastName, name)
			}
			lastPos = i + 1
			lastName = name
		}
	}
	if lastPos == n {
		return fmt.Errorf("%w: %s", ErrFencedTrailing, lastName)
	}
	return nil
}
```

### checkValidLabel() - Label Validation Orchestrator (lines 288-329)

```go
func (l *ENSIP15) checkValidLabel(cps []rune, tokens []OutputToken) (*Group, error) {
	if len(cps) == 0 {
		return nil, ErrEmptyLabel
	}
	if err := checkLeadingUnderscore(cps); err != nil {
		return nil, err
	}
	hasEmoji := len(tokens) > 1 || tokens[0].Emoji != nil
	if !hasEmoji && isASCII(cps) {
		if err := checkLabelExtension(cps); err != nil {
			return nil, err
		}
		return l._ASCII, nil
	}
	chars := make([]rune, 0, len(cps))
	for _, t := range tokens {
		if t.Emoji == nil {
			chars = append(chars, t.Codepoints...)
		}
	}
	if hasEmoji && len(chars) == 0 {
		return l._EMOJI, nil
	}
	if err := l.checkCombiningMarks(tokens); err != nil {
		return nil, err
	}
	if err := l.checkFenced(cps); err != nil {
		return nil, err
	}
	unique := uniqueRunes(chars)
	group, err := l.determineGroup(unique)
	if err != nil {
		return nil, err
	}
	if err := l.checkGroup(group, chars); err != nil {
		return nil, err
	}
	if err := l.checkWhole(group, unique); err != nil {
		return nil, err
	}
	return group, nil
}
```

## Implementation Guidance

### Normalization Pipeline Overview

The normalization process follows this pipeline:

1. **Split** the input name by dots into labels
2. **For each label**:
   - Convert to Unicode codepoints (runes)
   - **Tokenize** into Text and Emoji tokens
   - **Apply NFC** normalization to text tokens
   - **Strip FE0F** from emoji tokens (use normalized form)
   - **Flatten** tokens back to codepoints
   - **Validate** the label:
     - Check for empty label
     - Check underscore rules
     - Determine if ASCII/Emoji/Script
     - Check combining marks
     - Check fenced characters
     - Determine script group
     - Check confusables
   - Replace label with normalized form
3. **Join** labels back with dots

### Zig Implementation Strategy

For this task, we're creating the structure and method signatures. Most validation logic will stub with `unreachable`.

#### Method Signatures

```zig
/// Main normalization entry point
/// Takes a name and returns its ENSIP15 normalized form
pub fn normalize(self: *const Ensip15, allocator: Allocator, name: []const u8) ![]u8 {
    // TODO: Call transform with appropriate parameters
    unreachable;
}

/// Internal transformation pipeline
/// Handles splitting, tokenizing, normalizing, and joining
fn transform(
    self: *const Ensip15,
    allocator: Allocator,
    name: []const u8,
    // Function pointers for normalization strategies will be needed
) ![]u8 {
    // TODO: Implement pipeline
    unreachable;
}
```

#### Validation Helper Functions

All should be stubbed with `unreachable` for now:

```zig
/// Check that underscores only appear at the start of label
fn checkLeadingUnderscore(cps: []const u21) !void {
    unreachable;
}

/// Check label extension format (3rd and 4th chars cannot both be hyphen)
fn checkLabelExtension(cps: []const u21) !void {
    unreachable;
}

/// Check combining mark placement rules
fn checkCombiningMarks(self: *const Ensip15, tokens: []const OutputToken) !void {
    _ = self;
    _ = tokens;
    unreachable;
}

/// Check fenced character placement (ZWJ/ZWNJ)
fn checkFenced(self: *const Ensip15, cps: []const u21) !void {
    _ = self;
    _ = cps;
    unreachable;
}

/// Orchestrates all label validation checks
fn checkValidLabel(
    self: *const Ensip15,
    allocator: Allocator,
    cps: []const u21,
    tokens: []const OutputToken,
) !?*const Group {
    _ = self;
    _ = allocator;
    _ = cps;
    _ = tokens;
    unreachable;
}
```

### Key Differences from Go

1. **Allocator**: Zig requires explicit memory management. The allocator is the first parameter after `self`.

2. **Error Handling**: Go uses `error` return values. Zig uses error union types: `![]u8` means "returns a slice or an error".

3. **Strings vs Slices**: Go's `string` becomes `[]const u8` (UTF-8 bytes) in Zig. Go's `[]rune` becomes `[]const u21` (Unicode codepoints) in Zig.

4. **Function Pointers**: Go's closures will need to be replaced with function pointers or different strategies in Zig.

5. **String Building**: Go's string concatenation will need to use ArrayList(u8) in Zig.

### Underscore Rule Details

The underscore rule is: underscores are only allowed at the start of a label (matching regex `/^_*[^_]*$/`).

Valid examples:
- `_abc` (leading underscore)
- `__test` (multiple leading underscores)
- `hello` (no underscores)

Invalid examples:
- `ab_c` (underscore in middle)
- `abc_` (trailing underscore)
- `_a_b` (underscore after non-underscore)

### Label Extension Rule Details

The label extension rule prevents confusion with ACE prefix format. The 3rd and 4th characters (indices 2 and 3) cannot both be hyphens.

Invalid examples:
- `xn--test` (ACE prefix format)
- `ab--cd` (hyphens at positions 2-3)

Valid examples:
- `ab-cd` (single hyphen)
- `abc--d` (hyphens not at positions 2-3)
- `-abc-` (hyphens at other positions)

## Helper Functions Required

These helper functions will be needed (implement in later tasks or as separate utilities):

### String Utilities (likely from Task 12)

```zig
/// Split name by dots into labels
fn split(allocator: Allocator, name: []const u8) ![][]const u8;

/// Join labels with dots
fn join(allocator: Allocator, labels: [][]const u8) ![]u8;

/// Flatten tokens into codepoint slice
fn flattenTokens(allocator: Allocator, tokens: []const OutputToken) ![]u21;
```

### Validation Utilities

```zig
/// Check if all codepoints are ASCII
fn isASCII(cps: []const u21) bool;

/// Get unique codepoints preserving order
fn uniqueRunes(allocator: Allocator, cps: []const u21) ![]u21;
```

## File Location

Add these methods to:

```
src/ensip15/ensip15.zig
```

This should be added to the main ENSIP15 struct implementation file created in Task 11.

## Dependencies

### Required Prior Tasks

- **Task 11**: ENSIP15 struct initialization
- **Task 12**: Utility functions (Split, Join, flattenTokens, isASCII, uniqueRunes)
- **Task 06**: OutputToken types
- **Task 07**: Error types
- **Task 10**: NFC normalization method

### Required Imports

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
const OutputToken = @import("types.zig").OutputToken;
const Group = @import("types.zig").Group;
const Error = @import("errors.zig").Error;
```

## Implementation Checklist

### Success Criteria

- [ ] `normalize()` public method defined
  - Signature: `pub fn normalize(self: *const Ensip15, allocator: Allocator, name: []const u8) ![]u8`
  - Returns error union type `![]u8`
  - Allocator is first parameter after self
  - Stubs with `unreachable`

- [ ] `transform()` helper method defined
  - Private method (no `pub`)
  - Takes name, allocator, and strategy parameters
  - Returns `![]u8`
  - Stubs with `unreachable`

- [ ] `checkLeadingUnderscore()` defined
  - Function (not method)
  - Takes codepoint slice
  - Returns error union `!void`
  - Stubs with `unreachable`

- [ ] `checkLabelExtension()` defined
  - Function (not method)
  - Takes codepoint slice
  - Returns error union `!void`
  - Stubs with `unreachable`

- [ ] `checkCombiningMarks()` defined
  - Method on Ensip15
  - Takes token slice
  - Returns error union `!void`
  - Stubs with `unreachable`

- [ ] `checkFenced()` defined
  - Method on Ensip15
  - Takes codepoint slice
  - Returns error union `!void`
  - Stubs with `unreachable`

- [ ] `checkValidLabel()` defined
  - Method on Ensip15
  - Takes allocator, codepoint slice, and token slice
  - Returns error union `!?*const Group` (optional Group pointer)
  - Stubs with `unreachable`

- [ ] All methods properly documented
  - Doc comments using `///`
  - Explain purpose and parameters
  - Note stub status

- [ ] File compiles without errors
- [ ] `zig build` succeeds

### Method Signatures Checklist

Verify each signature matches these exact forms:

```zig
// Public API
pub fn normalize(self: *const Ensip15, allocator: Allocator, name: []const u8) ![]u8

// Internal pipeline
fn transform(
    self: *const Ensip15,
    allocator: Allocator,
    name: []const u8,
    // Additional parameters TBD
) ![]u8

// Validation helpers (functions, not methods)
fn checkLeadingUnderscore(cps: []const u21) !void
fn checkLabelExtension(cps: []const u21) !void

// Validation helpers (methods on Ensip15)
fn checkCombiningMarks(self: *const Ensip15, tokens: []const OutputToken) !void
fn checkFenced(self: *const Ensip15, cps: []const u21) !void
fn checkValidLabel(
    self: *const Ensip15,
    allocator: Allocator,
    cps: []const u21,
    tokens: []const OutputToken,
) !?*const Group
```

## Validation Commands

After implementing, validate with:

```bash
# Build the project
zig build

# If tests exist
zig build test --summary all
```

The file should compile cleanly with all methods stubbed with `unreachable`.

## Example Implementation Structure

```zig
//! ENSIP15 Normalization Methods
//!
//! This file contains the main normalization pipeline and validation logic.

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import types from other modules
const OutputToken = @import("types.zig").OutputToken;
const Group = @import("types.zig").Group;
const Error = @import("errors.zig").Error;

// ... earlier parts of ensip15.zig ...

/// Normalize a name according to ENSIP15 specification
///
/// Takes an input name and returns its normalized form.
/// The normalized form is suitable for on-chain storage and comparison.
///
/// Parameters:
///   - allocator: Memory allocator for result
///   - name: Input name as UTF-8 bytes
///
/// Returns: Normalized name as UTF-8 bytes
///
/// Errors: See Error enum for all possible validation failures
///
/// Note: Currently stubbed with unreachable
pub fn normalize(self: *const Ensip15, allocator: Allocator, name: []const u8) ![]u8 {
    _ = self;
    _ = allocator;
    _ = name;
    unreachable; // TODO: Implement in future task
}

/// Internal transformation pipeline
///
/// Orchestrates: split → tokenize → normalize → validate → join
///
/// Note: Currently stubbed with unreachable
fn transform(
    self: *const Ensip15,
    allocator: Allocator,
    name: []const u8,
    // TODO: Add function pointer parameters for NFC and emoji strategies
) ![]u8 {
    _ = self;
    _ = allocator;
    _ = name;
    unreachable; // TODO: Implement in future task
}

/// Check that underscores only appear at start of label
///
/// Valid: "_test", "__abc", "hello"
/// Invalid: "ab_c", "test_", "_a_b"
///
/// Note: Currently stubbed with unreachable
fn checkLeadingUnderscore(cps: []const u21) !void {
    _ = cps;
    unreachable; // TODO: Implement in future task
}

/// Check label extension format
///
/// The 3rd and 4th characters (indices 2-3) cannot both be hyphens.
/// This prevents confusion with ACE prefix format (xn--).
///
/// Note: Currently stubbed with unreachable
fn checkLabelExtension(cps: []const u21) !void {
    _ = cps;
    unreachable; // TODO: Implement in future task
}

/// Check combining mark placement rules
///
/// Combining marks cannot:
/// - Appear at start of label
/// - Appear after emoji
///
/// Note: Currently stubbed with unreachable
fn checkCombiningMarks(self: *const Ensip15, tokens: []const OutputToken) !void {
    _ = self;
    _ = tokens;
    unreachable; // TODO: Implement in future task
}

/// Check fenced character placement (ZWJ/ZWNJ)
///
/// Fenced characters cannot:
/// - Appear at start of label
/// - Appear at end of label
/// - Appear adjacent to each other
///
/// Note: Currently stubbed with unreachable
fn checkFenced(self: *const Ensip15, cps: []const u21) !void {
    _ = self;
    _ = cps;
    unreachable; // TODO: Implement in future task
}

/// Orchestrate all label validation checks
///
/// Determines label type (ASCII, Emoji, or script group) and validates accordingly.
///
/// Returns: The Group this label belongs to, or null for ASCII/Emoji
///
/// Note: Currently stubbed with unreachable
fn checkValidLabel(
    self: *const Ensip15,
    allocator: Allocator,
    cps: []const u21,
    tokens: []const OutputToken,
) !?*const Group {
    _ = self;
    _ = allocator;
    _ = cps;
    _ = tokens;
    unreachable; // TODO: Implement in future task
}
```

## Common Pitfalls

### Avoid These Mistakes

1. **Allocator Position**: The allocator must be the first parameter after `self`, not last:
   - ❌ `fn normalize(self: *const Ensip15, name: []const u8, allocator: Allocator)`
   - ✅ `fn normalize(self: *const Ensip15, allocator: Allocator, name: []const u8)`

2. **Return Type**: Use error union type with allocated slice:
   - ❌ `fn normalize(...) []u8` (no error handling)
   - ❌ `fn normalize(...) Error![]const u8` (const prevents ownership transfer)
   - ✅ `fn normalize(...) ![]u8` (inferred error set with mutable slice)

3. **String Types**: UTF-8 strings are `[]const u8`, Unicode codepoints are `[]const u21`:
   - ❌ `name: []u8` (should be const for input)
   - ❌ `cps: []rune` (Zig doesn't have rune type)
   - ✅ `name: []const u8` (UTF-8 input)
   - ✅ `cps: []const u21` (Unicode codepoints)

4. **Function vs Method**: Helper functions without `self` should not be methods:
   - ❌ `fn checkLeadingUnderscore(self: *const Ensip15, cps: []const u21)`
   - ✅ `fn checkLeadingUnderscore(cps: []const u21)`

5. **Unused Parameters in Stubs**: Mark unused parameters with `_ =`:
   ```zig
   fn checkFenced(self: *const Ensip15, cps: []const u21) !void {
       _ = self;  // Avoid unused parameter warning
       _ = cps;   // Avoid unused parameter warning
       unreachable;
   }
   ```

6. **Memory Leaks**: Remember that returned slices must be freed by caller:
   ```zig
   // Caller's responsibility:
   const result = try ensip15.normalize(allocator, input);
   defer allocator.free(result);
   ```

7. **Error Context**: Don't implement error message formatting yet. Just stub the functions:
   - ❌ Trying to format error messages now
   - ✅ Simple `unreachable` stub

8. **Implementing Too Much**: This task is about structure, not implementation:
   - ❌ Actually implementing validation logic
   - ✅ Creating signatures and stubbing with `unreachable`

## Testing Strategy

For this task, compilation is the test. The methods are stubbed and will be implemented in future tasks.

Once implemented, test cases would include:

```zig
test "normalize basic ASCII" {
    const allocator = std.testing.allocator;
    const ensip15 = try Ensip15.init(allocator);
    defer ensip15.deinit();

    const result = try ensip15.normalize(allocator, "hello.eth");
    defer allocator.free(result);

    try std.testing.expectEqualStrings("hello.eth", result);
}

test "normalize with emoji" {
    // Tests emoji normalization
}

test "normalize rejects invalid underscore" {
    const allocator = std.testing.allocator;
    const ensip15 = try Ensip15.init(allocator);
    defer ensip15.deinit();

    const result = ensip15.normalize(allocator, "ab_c.eth");
    try std.testing.expectError(Error.LeadingUnderscore, result);
}

test "normalize rejects label extension" {
    const allocator = std.testing.allocator;
    const ensip15 = try Ensip15.init(allocator);
    defer ensip15.deinit();

    const result = ensip15.normalize(allocator, "xn--test.eth");
    try std.testing.expectError(Error.InvalidLabelExtension, result);
}
```

## Architecture Notes

### Why Separate checkLeadingUnderscore from checkValidLabel?

The Go code separates these concerns for clarity:
- `checkLeadingUnderscore` and `checkLabelExtension` are pure functions
- `checkValidLabel` orchestrates all validation
- This separation makes testing and maintenance easier

### Why Return ?*const Group?

The `checkValidLabel` function returns an optional pointer to a Group because:
- ASCII labels return the `_ASCII` group
- Emoji labels return the `_EMOJI` group
- Script labels return their specific group (e.g., `_LATIN`, `_GREEK`)
- The group information is used for confusable checking

The optional (`?`) allows for the case where no group is assigned, though in practice all valid labels have a group.

### Transform Pattern

The `transform()` method is a higher-order function pattern:
- Takes function pointers for different normalization strategies
- `normalize()` uses NFC + normalized emoji
- `beautify()` (future task) uses NFC + beautified emoji
- `normalizeFragment()` (future task) uses NFC/NFD + normalized emoji

This is harder to express in Zig than Go, so the implementation may differ from the Go pattern.

## Next Steps

After completing this task:

1. **Task 14**: Implement helper utilities (split, join, flattenTokens, etc.)
2. **Task 15**: Implement tokenization (outputTokenize method)
3. **Task 16**: Implement validation logic (fill in the unreachable stubs)
4. **Task 17**: Implement group determination and confusable checking
5. **Task 18**: Add comprehensive tests for normalization

The stubbed methods created here will be filled in progressively through these tasks.

## References

- [ENSIP15 Specification](https://docs.ens.domains/ens-improvement-proposals/ensip-15-normalization-standard)
- [Zig Error Handling](https://ziglang.org/documentation/master/#Errors)
- [Zig Memory Allocation](https://ziglang.org/documentation/master/#Allocators)
- Go Reference Implementation: `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/ensip15.go`
- Go Utils Reference: `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/utils.go`
- Go Output Types: `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/output.go`
