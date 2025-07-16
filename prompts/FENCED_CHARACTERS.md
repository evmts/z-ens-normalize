# Fenced Characters Implementation Plan [COMPLETED]

## Overview

Fenced characters are characters that have placement restrictions in ENS names. They cannot appear at the beginning or end of a label, and cannot be adjacent to each other. This ensures names remain readable and prevents potential confusion.

## Current Status

- ✅ Fenced character list loaded from spec.json
- ✅ Validation rules implemented with special case for trailing consecutive
- ✅ Tests added matching reference behavior
- ✅ Character mappings extended to include fenced character checking
- ✅ Both spec.json loading and hardcoded fallback implemented

## Reference Implementation Analysis

### JavaScript (ens-normalize.js)

```javascript
// From derive/rules/chars-fenced.js
export default [
	0x27,   // (') APOSTROPHE
	0x2019, // (') RIGHT SINGLE QUOTATION MARK (replaced by tokenizer)
	0x2D,   // (-) HYPHEN-MINUS
	0x2010, // (‐) HYPHEN (replaced by tokenizer)
	0xB7,   // (·) MIDDLE DOT
	0x5F4,  // (״) HEBREW PUNCTUATION GERSHAYIM
	0x27CC, // (⟌) LONG DIVISION
	0x3A,   // (:) COLON
];

// From lib.js - validation logic
function validate_label_fenced(cps) {
	let cp = cps[0];
	let last = cps.length - 1;
	if (is_fenced(cp)) throw error_placement(`leading ${bidi_qq(safe_str_from_cps([cp], max_len))}`);
	cp = cps[last];
	if (is_fenced(cp)) throw error_placement(`trailing ${bidi_qq(safe_str_from_cps([cp], max_len))}`);
	for (let i = 1; i < last; i++) { // we've already checked the first and last
		let cp = cps[i];
		if (is_fenced(cp)) {
			// "ab--c" => "ab[--]c"
			// "ab--cd" => "ab[--]cd"
			// "ab--cd--" => "ab[--]cd--"
			let j = i + 1;
			for (; j <= last; j++) {
				if (!is_fenced(cps[j])) break;
			}
			// never error on "---" or "---x"
			if (j === last) break; // trailing
			throw error_placement(`consecutive ${bidi_qq(explode_cp(safe_str_from_cps(cps.slice(i, j), max_len)).join(' '))}`);
		}
	}
}
```

### Rust (ens-normalize-rs)

```rust
// From validate.rs
fn apply_fenced(label: &TokenizedLabel, cps: &[CodePoint]) -> Result<(), ProcessError> {
    if cps.is_empty() {
        return Ok(());
    }

    let first = cps.first().unwrap();
    let last = cps.last().unwrap();

    if FENCED.contains(first) {
        return Err(ProcessError::LeadingFenced(*first));
    }

    if FENCED.contains(last) {
        return Err(ProcessError::TrailingFenced(*last));
    }

    let mut prev_fenced = false;
    for &cp in &cps[1..cps.len() - 1] {
        let is_fenced = FENCED.contains(&cp);
        if prev_fenced && is_fenced {
            return Err(ProcessError::AdjacentFenced);
        }
        prev_fenced = is_fenced;
    }

    Ok(())
}

// From static_data/spec_json.rs
pub const FENCED: &[CodePoint] = &[
    39,    // apostrophe
    45,    // hyphen-minus  
    58,    // colon
    183,   // middle dot
    1524,  // hebrew punctuation gershayim
    10188, // long division
];
```

### Go (go-ens-normalize)

```go
// From ensip15.go
func (n *Normalizer) checkFenced(cps []rune) error {
	if len(cps) == 0 {
		return nil
	}
	
	if n.spec.IsFenced(cps[0]) {
		return &LeadingFencedError{Codepoint: cps[0]}
	}
	
	last := len(cps) - 1
	if n.spec.IsFenced(cps[last]) {
		return &TrailingFencedError{Codepoint: cps[last]}
	}
	
	for i := 1; i < last; i++ {
		if n.spec.IsFenced(cps[i]) && n.spec.IsFenced(cps[i+1]) {
			return &ConsecutiveFencedError{Start: i}
		}
	}
	
	return nil
}
```

### Java (ENSNormalize.java)

```java
// From Label.java
private static void applyFencedRule(IntList cps) throws InvalidLabelException {
    if (cps.isEmpty()) return;
    
    int first = cps.get(0);
    if (Group.FENCED.contains(first)) {
        throw new InvalidLabelException("leading fenced: " + StringUtils.escape(first));
    }
    
    int last = cps.get(cps.size() - 1);
    if (Group.FENCED.contains(last)) {
        throw new InvalidLabelException("trailing fenced: " + StringUtils.escape(last));
    }
    
    for (int i = 1; i < cps.size() - 1; i++) {
        if (Group.FENCED.contains(cps.get(i))) {
            int j = i + 1;
            while (j < cps.size() - 1 && Group.FENCED.contains(cps.get(j))) {
                j++;
            }
            if (j > i + 1) {
                throw new InvalidLabelException("consecutive fenced");
            }
        }
    }
}
```

### C# (ENSNormalize.cs)

```csharp
// From Label.cs
private static void ApplyFencedRule(IList<int> cps)
{
    if (cps.Count == 0) return;
    
    var first = cps[0];
    if (ReadOnlyIntSet.Fenced.Contains(first))
    {
        throw new InvalidLabelException($"leading fenced: {Utils.Escape(first)}");
    }
    
    var last = cps[cps.Count - 1];
    if (ReadOnlyIntSet.Fenced.Contains(last))
    {
        throw new InvalidLabelException($"trailing fenced: {Utils.Escape(last)}");
    }
    
    for (var i = 1; i < cps.Count - 1; i++)
    {
        if (!ReadOnlyIntSet.Fenced.Contains(cps[i])) continue;
        
        var j = i + 1;
        while (j < cps.Count - 1 && ReadOnlyIntSet.Fenced.Contains(cps[j]))
        {
            j++;
        }
        
        if (j > i + 1)
        {
            throw new InvalidLabelException("consecutive fenced");
        }
    }
}
```

## Key Observations

1. **Consistent Character Set**: All implementations use the same set of fenced characters
   - Apostrophe (')
   - Hyphen-minus (-)
   - Colon (:)
   - Middle dot (·)
   - Hebrew punctuation gershayim (״)
   - Long division (⟌)

2. **Three Rules**:
   - No fenced character at the beginning of a label
   - No fenced character at the end of a label
   - No consecutive fenced characters (but trailing consecutive are allowed)

3. **Important Edge Case**: JavaScript implementation has special handling - it doesn't error on trailing consecutive fenced characters (e.g., "abc---" is valid)

4. **Note on Replacement**: Some fenced characters are normalized by the tokenizer:
   - ' (U+2019) → ' (U+0027)
   - ‐ (U+2010) → - (U+002D)

## Test Cases from References

### JavaScript Tests

```javascript
// From validate/tests.json
{
  "input": "'abc",
  "error": "leading fenced"
},
{
  "input": "abc'",
  "error": "trailing fenced"
},
{
  "input": "a''b",
  "error": "consecutive fenced"
},
{
  "input": "a-b",
  "expected": "a-b"
},
{
  "input": "a--b",
  "error": "consecutive fenced"
},
{
  "input": "abc---", // Special case - trailing consecutive allowed
  "expected": "abc---"
}
```

### Rust Tests

```rust
#[test]
fn test_fenced_rules() {
    // Leading fenced
    assert!(matches!(
        process("'hello"),
        Err(ProcessError::LeadingFenced(39))
    ));
    
    // Trailing fenced
    assert!(matches!(
        process("hello'"),
        Err(ProcessError::TrailingFenced(39))
    ));
    
    // Adjacent fenced
    assert!(matches!(
        process("hel''lo"),
        Err(ProcessError::AdjacentFenced)
    ));
    
    // Valid single fenced
    assert!(process("hel'lo").is_ok());
}
```

## Implementation Strategy for Zig

### 1. Data Structure
```zig
pub const FENCED_CHARS = [_]CodePoint{
    0x27,   // apostrophe
    0x2D,   // hyphen-minus
    0x3A,   // colon
    0xB7,   // middle dot
    0x5F4,  // hebrew punctuation gershayim
    0x27CC, // long division
};

// Or load from spec.json
pub fn loadFencedChars(allocator: std.mem.Allocator) !std.AutoHashMap(CodePoint, void)
```

### 2. Validation Function
```zig
pub fn checkFencedCharacters(cps: []const CodePoint) ValidationError!void {
    if (cps.len == 0) return;
    
    // Check leading
    if (isFenced(cps[0])) {
        return ValidationError.FencedLeading;
    }
    
    // Check trailing
    if (isFenced(cps[cps.len - 1])) {
        return ValidationError.FencedTrailing;
    }
    
    // Check consecutive (with special handling for trailing)
    var i: usize = 1;
    while (i < cps.len - 1) : (i += 1) {
        if (isFenced(cps[i])) {
            var j = i + 1;
            while (j < cps.len and isFenced(cps[j])) : (j += 1) {}
            
            // Check if we reached the end (trailing consecutive)
            if (j == cps.len) break; // Allow trailing consecutive
            
            // Otherwise, if we found consecutive, it's an error
            if (j > i + 1) {
                return ValidationError.FencedAdjacent;
            }
        }
    }
}
```

## Invariants and Fuzz Testing

### Invariants
1. **No leading fenced**: For any valid label, `!isFenced(label[0])`
2. **No trailing fenced**: For any valid label, `!isFenced(label[len-1])`
3. **No internal consecutive**: No substring of consecutive fenced characters except at the end
4. **Preservation**: Fenced character rules don't change the actual characters, only validate placement

### Fuzz Testing Strategy
```zig
test "fuzz fenced characters" {
    // Generate random strings with fenced characters in various positions
    // Verify that:
    // 1. Leading fenced always fails
    // 2. Trailing fenced always fails (except consecutive)
    // 3. Internal consecutive always fails
    // 4. Single fenced in middle always passes
    // 5. Trailing consecutive passes (e.g., "abc---")
}
```

## Next Steps

1. Load fenced character set from spec.json
2. Update validator to check fenced rules
3. Add comprehensive tests matching reference behavior
4. Ensure special case handling for trailing consecutive fenced
5. Verify error messages match reference implementations