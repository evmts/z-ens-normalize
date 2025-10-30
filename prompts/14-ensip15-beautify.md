# Task 14: Implement ENSIP15 beautify() Method

## Goal

Port the `beautify()` and `normalizeFragment()` methods from Go to Zig in `src/ensip15/ensip15.zig`.

These methods are similar to `normalize()` but with key differences:
- **beautify()**: Preserves emoji presentation (keeps FE0F sequences) and converts Greek lowercase xi (ξ) to uppercase Xi (Ξ) for non-Greek names
- **normalizeFragment()**: Performs partial normalization without validation, useful for processing label fragments

Both methods reuse the existing `transform()` pipeline but with different emoji formatters and post-processing functions.

## Go Reference Code

Below is the complete reference implementation from Go:

### Beautify() Method (Lines 158-180)

```go
func (l *ENSIP15) Beautify(name string) (string, error) {
	return l.transform(
		name,
		l.nf.NFC,
		func(e EmojiSequence) []rune { return e.beautified },
		func(tokens []OutputToken) (string, error) {
			cps := FlattenTokens(tokens)
			g, err := l.checkValidLabel(cps, tokens)
			if err != nil {
				return "", err
			}
			if g != l._GREEK {
				for i, x := range cps {
					// ξ => Ξ if not greek
					if x == 0x3BE {
						cps[i] = 0x39E
					}
				}
			}
			return string(cps), nil
		},
	)
}
```

### NormalizeFragment() Method (Lines 182-195)

```go
func (l *ENSIP15) NormalizeFragment(frag string, decompose bool) (string, error) {
	nf := l.nf.NFC
	if decompose {
		nf = l.nf.NFD
	}
	return l.transform(
		frag,
		nf,
		func(e EmojiSequence) []rune { return e.normalized },
		func(tokens []OutputToken) (string, error) {
			return string(FlattenTokens(tokens)), nil
		},
	)
}
```

### Transform() Method Signature (Lines 197-202)

For reference, here's the `transform()` signature these methods call:

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
			// ... applies normalizer function
		}
	}
}
```

## Implementation Guidance

### Key Differences from normalize()

The `beautify()` method differs from `normalize()` in two ways:

1. **Emoji Formatter**: Returns `emoji.beautified` instead of `emoji.normalized`
   - Beautified form preserves FE0F (variation selector) for emoji presentation
   - Normalized form removes FE0F for canonical form

2. **Post-Validation Processing**: After validation, converts lowercase Greek xi to uppercase
   - If the label's script group is NOT Greek, replace U+03BE (ξ) with U+039E (Ξ)
   - This ensures Greek letters appear capitalized in non-Greek contexts

### Understanding normalizeFragment()

The `normalizeFragment()` method is for partial normalization:

- **No Validation**: Skips `checkValidLabel()` and validation steps
- **Configurable Normalization**: Takes `decompose` parameter
  - `decompose = false`: Uses NFC (composed form)
  - `decompose = true`: Uses NFD (decomposed form)
- **Simple Output**: Just tokenizes and normalizes, returns flattened result
- **Use Case**: Processing label fragments or sub-components without full ENSIP15 validation

### Implementation Strategy

For this task, create stub implementations that:

1. **Define Function Signatures**: Match the expected Zig API
2. **Add Documentation**: Explain what each function will do
3. **Stub with unreachable**: Since dependencies aren't ready yet
4. **Maintain Consistency**: Follow patterns from `normalize()` stub

### Zig Function Signatures

```zig
/// Beautify an ENS name preserving emoji presentation and converting ξ→Ξ in non-Greek names.
///
/// This is similar to normalize() but:
/// - Uses beautified emoji forms (preserves FE0F variation selectors)
/// - Converts U+03BE (ξ) to U+039E (Ξ) if the label is not Greek
///
/// The beautified form is more visually appealing for display while still being
/// normalized according to ENSIP15.
///
/// Returns an allocated string that must be freed by the caller.
pub fn beautify(self: *const Ensip15, allocator: Allocator, name: []const u8) ![]u8 {
    _ = self;
    _ = allocator;
    _ = name;
    unreachable; // TODO: Implement in later task
}

/// Normalize a label fragment without validation.
///
/// This performs tokenization and normalization without the full ENSIP15 validation
/// checks. Useful for processing partial labels or components.
///
/// Parameters:
/// - frag: The label fragment to normalize
/// - decompose: If true, use NFD (decomposed); if false, use NFC (composed)
///
/// Returns an allocated string that must be freed by the caller.
pub fn normalizeFragment(self: *const Ensip15, allocator: Allocator, frag: []const u8, decompose: bool) ![]u8 {
    _ = self;
    _ = allocator;
    _ = frag;
    _ = decompose;
    unreachable; // TODO: Implement in later task
}
```

### Implementation Notes

1. **Reuse transform()**: Both methods will call the `transform()` helper with different parameters
2. **Emoji Formatter Parameter**: Pass different emoji formatters:
   - `beautify()`: `fn(emoji: EmojiSequence) []const u21 { return emoji.beautified; }`
   - `normalizeFragment()`: `fn(emoji: EmojiSequence) []const u21 { return emoji.normalized; }`
3. **Normalizer Parameter**: Different post-processing:
   - `beautify()`: Validates then converts ξ→Ξ if not Greek
   - `normalizeFragment()`: Just flattens tokens, no validation
4. **Greek Xi Conversion**: Check each codepoint after validation:
   ```zig
   if (group != self._GREEK) {
       for (cps) |*cp| {
           if (cp.* == 0x03BE) {  // ξ
               cp.* = 0x039E;      // Ξ
           }
       }
   }
   ```

## File Location

Add these methods to the existing file:

```
src/ensip15/ensip15.zig
```

These should be added as public methods on the `Ensip15` struct, alongside the existing `normalize()` method stub.

## Dependencies

### Required (from previous tasks):

- **Task 11**: ENSIP15 init with group references (for `self._GREEK`)
- **Task 13**: `normalize()` and `transform()` methods implemented

### Related Types:

- `EmojiSequence` struct with `beautified` and `normalized` fields
- `OutputToken` type
- `Group` type for script identification
- NFC/NFD normalization functions

## Implementation Checklist

### Success Criteria

- [ ] `beautify()` method signature matches specification
- [ ] `normalizeFragment()` method signature matches specification
- [ ] Both methods have comprehensive documentation comments
- [ ] Documentation explains differences from `normalize()`
- [ ] beautify() docs mention emoji FE0F preservation
- [ ] beautify() docs mention ξ→Ξ conversion for non-Greek
- [ ] normalizeFragment() docs explain no validation occurs
- [ ] normalizeFragment() docs explain decompose parameter
- [ ] Both methods stub with `unreachable` for now
- [ ] File compiles without errors
- [ ] `zig build` succeeds

### Code Quality

- [ ] Function signatures follow Zig conventions
- [ ] Documentation uses proper doc comment format (`///`)
- [ ] Parameter descriptions are clear
- [ ] Return value semantics documented (caller must free)
- [ ] Unused parameters suppressed with `_ = param;`
- [ ] Consistent style with existing `normalize()` stub

## Validation Commands

After implementing, validate with:

```bash
# Build the project
zig build

# Check for compilation errors in the ensip15 module
zig build-lib src/ensip15/ensip15.zig

# If tests exist
zig build test --summary all
```

The file should compile cleanly with no errors. The methods won't be callable yet (they use `unreachable`), but the signatures and documentation should be complete.

## Common Pitfalls

### Avoid These Mistakes

1. **Duplicating transform() Logic**:
   - ❌ Copying the entire transform pipeline into each method
   - ✅ Both methods should call `transform()` with different parameters

2. **Wrong Emoji Form**:
   - ❌ Using `emoji.normalized` in beautify()
   - ✅ Using `emoji.beautified` in beautify()
   - ❌ Using `emoji.beautified` in normalizeFragment()
   - ✅ Using `emoji.normalized` in normalizeFragment()

3. **Greek Xi Conversion Errors**:
   - ❌ Converting ξ→Ξ in ALL labels
   - ✅ Only convert if `group != self._GREEK`
   - ❌ Checking for uppercase Ξ (0x039E)
   - ✅ Checking for lowercase ξ (0x03BE)

4. **Validation in normalizeFragment()**:
   - ❌ Calling `checkValidLabel()` in normalizeFragment
   - ✅ No validation, just tokenize and normalize

5. **Wrong Normalization Form**:
   - ❌ Always using NFC in normalizeFragment
   - ✅ Choose NFC or NFD based on `decompose` parameter

6. **Memory Management**:
   - ❌ Forgetting to document that caller must free result
   - ✅ Clear documentation about memory ownership

7. **Parameter Order**:
   - ❌ `normalizeFragment(self, frag, allocator, decompose)`
   - ✅ `normalizeFragment(self, allocator, frag, decompose)`
   - Follow Zig convention: allocator comes early in parameter list

## Example Implementation Structure

```zig
pub const Ensip15 = struct {
    // ... existing fields ...

    /// Normalize an ENS name to its canonical form.
    pub fn normalize(self: *const Ensip15, allocator: Allocator, name: []const u8) ![]u8 {
        _ = self;
        _ = allocator;
        _ = name;
        unreachable; // TODO: Implement in later task
    }

    /// Beautify an ENS name preserving emoji presentation and converting ξ→Ξ in non-Greek names.
    ///
    /// This is similar to normalize() but:
    /// - Uses beautified emoji forms (preserves FE0F variation selectors)
    /// - Converts U+03BE (ξ) to U+039E (Ξ) if the label is not Greek
    ///
    /// The beautified form is more visually appealing for display while still being
    /// normalized according to ENSIP15.
    ///
    /// Returns an allocated string that must be freed by the caller.
    pub fn beautify(self: *const Ensip15, allocator: Allocator, name: []const u8) ![]u8 {
        _ = self;
        _ = allocator;
        _ = name;
        unreachable; // TODO: Implement in later task
    }

    /// Normalize a label fragment without validation.
    ///
    /// This performs tokenization and normalization without the full ENSIP15 validation
    /// checks. Useful for processing partial labels or components.
    ///
    /// Parameters:
    /// - frag: The label fragment to normalize
    /// - decompose: If true, use NFD (decomposed); if false, use NFC (composed)
    ///
    /// Returns an allocated string that must be freed by the caller.
    pub fn normalizeFragment(self: *const Ensip15, allocator: Allocator, frag: []const u8, decompose: bool) ![]u8 {
        _ = self;
        _ = allocator;
        _ = frag;
        _ = decompose;
        unreachable; // TODO: Implement in later task
    }

    // ... other methods ...
};
```

## Unicode Reference

### Greek Xi Codepoints

- **Lowercase ξ**: U+03BE (GREEK SMALL LETTER XI)
  - Decimal: 958
  - Hex: 0x3BE

- **Uppercase Ξ**: U+039E (GREEK CAPITAL LETTER XI)
  - Decimal: 926
  - Hex: 0x39E

### Emoji Variation Selectors

- **FE0F**: Emoji Presentation (colored emoji style)
- **FE0E**: Text Presentation (black & white text style)

Beautified form preserves FE0F to maintain emoji appearance in display contexts.

## Testing Strategy

For this task, basic compilation is sufficient. The actual functionality will be tested when the methods are implemented in later tasks.

When implementing, test cases should cover:

1. **beautify() Tests**:
   - Emoji with FE0F preserved
   - Greek name with ξ preserved
   - Non-Greek name with ξ converted to Ξ
   - Mixed script validation

2. **normalizeFragment() Tests**:
   - Fragment with NFC normalization
   - Fragment with NFD normalization
   - Invalid characters allowed (no validation)
   - Partial label processing

## Next Steps

After completing this task:

1. The method signatures will be in place for future implementation
2. Documentation will guide implementation work
3. API surface area is defined for consumers
4. Task 15+ will implement the actual logic using the transform() pipeline

## References

- [ENSIP15 Specification](https://docs.ens.domains/ens-improvement-proposals/ensip-15-normalization-standard)
- [Unicode Greek and Coptic Block](https://unicode.org/charts/PDF/U0370.pdf)
- [Emoji Variation Selectors](https://unicode.org/reports/tr51/#Emoji_Variation_Sequences)
- Go Reference Implementation: `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/ensip15.go` (lines 158-195)
