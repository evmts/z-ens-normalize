# Task 07: Define Error Types

## Goal

Port all ENSIP15 error types from Go to Zig as an error set in `src/ensip15/errors.zig`.

This task creates the foundational error types that will be used throughout the ENSIP15 normalization implementation. In Zig, errors are defined as error sets, which are enum-like types that can be returned from functions.

## Go Reference Code

Below is the complete `errors.go` file from the Go implementation:

```go
package ensip15

import "fmt"

var (
	ErrInvalidLabelExtension = fmt.Errorf("invalid label extension")
	ErrIllegalMixture        = fmt.Errorf("illegal mixture")
	ErrWholeConfusable       = fmt.Errorf("whole-script confusable")
	ErrLeadingUnderscore     = fmt.Errorf("underscore allowed only at start")
	ErrFencedLeading         = fmt.Errorf("leading fenced")
	ErrFencedAdjacent        = fmt.Errorf("adjacent fenced")
	ErrFencedTrailing        = fmt.Errorf("trailing fenced")
	ErrDisallowedCharacter   = fmt.Errorf("disallowed character")
	ErrEmptyLabel            = fmt.Errorf("empty label")
	ErrCMLeading             = fmt.Errorf("leading combining mark")
	ErrCMAfterEmoji          = fmt.Errorf("emoji + combining mark")
	ErrNSMDuplicate          = fmt.Errorf("duplicate non-spacing marks")
	ErrNSMExcessive          = fmt.Errorf("excessive non-spacing marks")
)

func (l *ENSIP15) createMixtureError(group *Group, cp rune) error {
	conflict := l.SafeCodepoint(cp)
	var other *Group
	for _, g := range l.groups {
		if g.primary.Contains(cp) {
			other = g
			break
		}
	}
	if other != nil {
		conflict = fmt.Sprintf("%s %s", other, conflict)
	}
	return fmt.Errorf("%w: %s + %s", ErrIllegalMixture, group, conflict)
}
```

## Implementation Guidance

### Error Set Definition

In Zig, errors are defined as error sets. Unlike Go's error values, Zig errors are compile-time known types that form part of the function signature.

Define the main error set as:

```zig
pub const Error = error{
    InvalidLabelExtension,
    IllegalMixture,
    WholeConfusable,
    LeadingUnderscore,
    FencedLeading,
    FencedAdjacent,
    FencedTrailing,
    DisallowedCharacter,
    EmptyLabel,
    CMLeading,
    CMAfterEmoji,
    NSMDuplicate,
    NSMExcessive,
    OutOfMemory,
};
```

### Key Differences from Go

1. **Error Names**: Strip the `Err` prefix from Go names, keeping PascalCase:
   - `ErrInvalidLabelExtension` → `InvalidLabelExtension`
   - `ErrIllegalMixture` → `IllegalMixture`
   - etc.

2. **Additional Error**: Add `OutOfMemory` to handle memory allocation failures that may occur during string processing.

3. **No Error Messages**: Unlike Go, Zig error sets don't contain messages. Error messages are typically constructed at the call site or by error handling functions.

### Helper Functions (Optional)

You can define helper functions for creating formatted error messages. For example, stub out the `createMixtureError` concept:

```zig
/// Placeholder for creating detailed mixture error messages
/// In the full implementation, this would format information about
/// which character groups are conflicting
pub fn createMixtureError(
    allocator: std.mem.Allocator,
    group_name: []const u8,
    codepoint: u21,
) Error![]const u8 {
    _ = allocator;
    _ = group_name;
    _ = codepoint;
    return Error.IllegalMixture;
}
```

For now, the helper function can be a stub. The main goal is to define the error set itself.

## Zig Error Syntax Reference

### Basic Error Set

```zig
pub const Error = error{
    ErrorName1,
    ErrorName2,
    ErrorName3,
};
```

### Error Union Types

Functions that can fail return error union types:

```zig
fn doSomething() Error!void {
    return Error.SomeError;
}

fn calculate() Error!i32 {
    if (bad_condition) return Error.SomeError;
    return 42;
}
```

### Combining Error Sets

Error sets can be combined with the `||` operator:

```zig
fn complexOperation() (Error || std.fs.File.WriteError)!void {
    // can return errors from both sets
}
```

## File Location

Create the file at:

```
src/ensip15/errors.zig
```

## Dependencies

This file is standalone and has no dependencies on other ENSIP15 modules. It only needs the Zig standard library:

```zig
const std = @import("std");
```

## Implementation Checklist

### Success Criteria

- [ ] File `src/ensip15/errors.zig` exists
- [ ] Error set `Error` is defined with all error types from Go reference
- [ ] `OutOfMemory` error is included for allocation failures
- [ ] All error names follow Zig naming conventions (PascalCase, no `Err` prefix)
- [ ] File compiles without errors
- [ ] File includes documentation comments explaining the error set
- [ ] Optional: Stub helper function for `createMixtureError` is included

### Error Types to Include

Copy this checklist to verify all errors are defined:

- [ ] `InvalidLabelExtension` - Invalid label extension format
- [ ] `IllegalMixture` - Characters from incompatible script groups
- [ ] `WholeConfusable` - Entire label is confusable with another
- [ ] `LeadingUnderscore` - Underscore in invalid position
- [ ] `FencedLeading` - Leading fenced codepoint (ZWJ/ZWNJ)
- [ ] `FencedAdjacent` - Adjacent fenced codepoints
- [ ] `FencedTrailing` - Trailing fenced codepoint
- [ ] `DisallowedCharacter` - Character not in allowed set
- [ ] `EmptyLabel` - Label contains no characters
- [ ] `CMLeading` - Combining mark at start of label
- [ ] `CMAfterEmoji` - Combining mark after emoji
- [ ] `NSMDuplicate` - Duplicate non-spacing marks
- [ ] `NSMExcessive` - Too many non-spacing marks
- [ ] `OutOfMemory` - Memory allocation failure

## Validation Commands

After implementing, validate with:

```bash
# Build the project
zig build

# If tests exist for errors
zig build test --summary all
```

The file should compile cleanly with no errors.

## Example Implementation Structure

```zig
//! ENSIP15 Error Types
//!
//! This module defines all error types used in ENSIP15 normalization.
//! Errors cover various validation and normalization failures according
//! to the ENSIP15 specification.

const std = @import("std");

/// Error set for all ENSIP15 normalization errors
pub const Error = error{
    /// Invalid label extension format
    InvalidLabelExtension,

    /// Characters from incompatible script groups mixed in label
    IllegalMixture,

    /// Entire label is confusable with another script
    WholeConfusable,

    /// Underscore in invalid position (only allowed at start)
    LeadingUnderscore,

    /// Leading fenced codepoint (ZWJ/ZWNJ)
    FencedLeading,

    /// Adjacent fenced codepoints
    FencedAdjacent,

    /// Trailing fenced codepoint
    FencedTrailing,

    /// Character not in allowed set
    DisallowedCharacter,

    /// Label contains no characters
    EmptyLabel,

    /// Combining mark at start of label
    CMLeading,

    /// Combining mark immediately after emoji
    CMAfterEmoji,

    /// Duplicate non-spacing marks
    NSMDuplicate,

    /// Excessive non-spacing marks
    NSMExcessive,

    /// Memory allocation failure
    OutOfMemory,
};

// Optional helper functions can be added below
```

## Common Pitfalls

### Avoid These Mistakes

1. **Adding Extra Errors**: Only include errors defined in the Go reference. Don't add speculative errors.

2. **Wrong Naming**:
   - ❌ `ErrInvalidLabelExtension` (Go style)
   - ❌ `invalid_label_extension` (snake_case)
   - ✅ `InvalidLabelExtension` (Zig style)

3. **Missing OutOfMemory**: Always include `OutOfMemory` even though it's not in Go, as Zig requires explicit memory allocation handling.

4. **Error Messages in Set**: Don't try to add error messages to the error set definition. Messages are handled separately in Zig.

5. **Complex Helper Functions**: Keep any helper functions as stubs for now. Don't implement full error formatting logic yet.

## Testing Strategy

For this task, basic compilation is sufficient. Error types will be tested indirectly when used in normalization functions in later tasks.

Optional: You can write basic tests to verify the error set exists and can be used:

```zig
test "error types defined" {
    const err: Error = Error.IllegalMixture;
    try std.testing.expect(err == Error.IllegalMixture);
}

test "error union return" {
    const result: Error!void = Error.EmptyLabel;
    try std.testing.expectError(Error.EmptyLabel, result);
}
```

## Next Steps

After completing this task:

1. The error types will be imported by other ENSIP15 modules
2. Functions like `normalize()` and `beautify()` will return `Error!ResultType`
3. Validation functions will throw these specific errors when checks fail

This error set forms the contract between the normalization library and its consumers, allowing them to handle specific failure cases appropriately.

## References

- [Zig Error Documentation](https://ziglang.org/documentation/master/#Errors)
- [ENSIP15 Specification](https://docs.ens.domains/ens-improvement-proposals/ensip-15-normalization-standard)
- Go Reference Implementation: `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/errors.go`
