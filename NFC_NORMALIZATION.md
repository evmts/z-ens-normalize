# NFC Normalization Implementation Plan [COMPLETED]

## Overview

NFC (Normalization Form C - Canonical Decomposition followed by Canonical Composition) is a critical component of ENS normalization. It ensures that visually identical strings are represented consistently.

## Current Status

- ✅ Token type for NFC exists (`tokenizer.TokenType.nfc`)
- ✅ Data structure for NFC tokens exists
- ✅ `nfc_check` data loaded from spec.json (characters that need NFC checking)
- ✅ Actual NFC implementation complete in `nfc.zig`
- ✅ `apply_nfc` parameter properly integrated in tokenization
- ✅ NFC data loading from nf.json
- ✅ Hangul syllable handling
- ✅ Canonical ordering implementation
- ✅ Tests passing

## Reference Implementation Analysis

### JavaScript (ens-normalize.js)

```javascript
// nf.js - Custom implementation with:
// - Algorithmic Hangul handling
// - Decomposition mappings
// - Recomposition mappings  
// - Exclusions set
// - Combining class rankings

// Usage in tokenization:
let tokens = tokens_from_str(input, nf, ef);
// ...
let cps = nfc(cps0);
if (compare_arrays(cps, cps0)) { // bundle into an nfc token
    tokens.splice(start, end - start, {
        type: TY_NFC, 
        input: cps0,
        cps,
        tokens0: collapse_valid_tokens(slice),
    });
}
```

### Rust (ens-normalize-rs)

```rust
use unicode_normalization::UnicodeNormalization;

pub fn nfc(str: &str) -> String {
    str.nfc().collect()
}

// In tokenization:
if apply_nfc {
    perform_nfc_transform(&mut tokens, specs);
}

// NFC transform logic:
let str0 = utils::cps2str(&cps);
let str = utils::nfc(&str0);
let cps_nfc = utils::str2cps(&str);
if cps != cps_nfc {
    // Create NFC token
}
```

### Go (go-ens-normalize)

```go
import "golang.org/x/text/unicode/norm"

// Uses standard Go normalization package
nfc := norm.NFC.String(input)
```

### Key Observations

1. **All implementations use Unicode NFC algorithm**
2. **NFC tokens are created when normalization changes the codepoints**
3. **The `nfc_check` set optimizes by only checking specific characters**
4. **Hangul syllables have special algorithmic handling**

## Implementation Strategy for Zig

### Option 1: Use Existing Library (Recommended for Phase 1)
- Find or create bindings to ICU or similar Unicode library
- Ensures correctness and compliance
- Faster to implement

### Option 2: Implement from Scratch (Future Enhancement)
- Study Unicode Standard Annex #15
- Implement decomposition tables
- Implement composition algorithm
- Handle Hangul algorithmically

### Option 3: Hybrid Approach
- Start with simplified implementation for common cases
- Use lookup tables from spec.json/nf.json
- Add full support incrementally

## Required Components

### 1. NFC Data Structures
```zig
pub const NFCData = struct {
    decomp: std.AutoHashMap(CodePoint, []const CodePoint),
    recomp: std.AutoHashMap(CodePointPair, CodePoint),
    exclusions: std.AutoHashMap(CodePoint, void),
    combining_class: std.AutoHashMap(CodePoint, u8),
};
```

### 2. Core Functions
```zig
// Main NFC function
pub fn nfc(allocator: std.mem.Allocator, cps: []const CodePoint) ![]CodePoint

// Helper functions
fn decompose(allocator: std.mem.Allocator, cps: []const CodePoint) ![]CodePoint
fn recompose(allocator: std.mem.Allocator, cps: []const CodePoint) ![]CodePoint
fn getCombiningClass(cp: CodePoint) u8
fn isHangulSyllable(cp: CodePoint) bool
fn decomposeHangul(cp: CodePoint) [3]CodePoint
fn composeHangul(l: CodePoint, v: CodePoint, t: ?CodePoint) ?CodePoint
```

### 3. Integration with Tokenizer
```zig
fn applyNFCTransform(allocator: std.mem.Allocator, tokens: *std.ArrayList(Token)) !void {
    var i: usize = 0;
    while (i < tokens.items.len) {
        // Check if token needs NFC
        if (needsNFCCheck(tokens.items[i])) {
            // Apply NFC and create new token if changed
        }
        i += 1;
    }
}
```

## Test Cases from References

### JavaScript Tests
```javascript
// From ens-normalize.js tests
assert(nfc("café") === "café");  // é remains composed
assert(nfc("café") === "café");  // e + ́ becomes é
```

### Rust Tests
```rust
// From tokenize.rs
#[case::with_nfc(
    "_R💩\u{FE0F}a\u{FE0F}\u{304}\u{AD}.",
    true,
    vec![
        // Creates NFC token for "a\u{304}" -> "ā"
    ]
)]
```

## Data Sources

1. **nf.json** - Contains decomposition and composition mappings
2. **spec.json** - Contains `nfc_check` set
3. **Unicode data files** - For complete implementation

## Implementation Completed

### What Was Implemented

1. **Core NFC Module (`nfc.zig`)**:
   - Full decomposition algorithm with recursive handling
   - Canonical ordering based on combining classes
   - Composition algorithm with exclusion handling
   - Algorithmic Hangul syllable decomposition/composition
   - NFCData structure for holding all normalization data

2. **Data Loading (`static_data_loader.zig`)**:
   - Loading decomposition mappings from nf.json
   - Loading exclusions set
   - Loading combining class rankings
   - Loading nfc_check set from spec.json
   - Building recomposition mappings from decomposition data

3. **Tokenizer Integration**:
   - `applyNFCTransform` function that checks tokens for NFC requirements
   - Creates NFC tokens when normalization changes the codepoints
   - Properly handles sequences of valid/mapped tokens
   - Skips ignored tokens but includes them in the range

4. **Utils Integration**:
   - Updated `nfc` function to use the full implementation
   - Converts string → codepoints → normalized codepoints → string

### Key Design Decisions

1. **Memory Management**: All allocated memory is properly tracked and freed
2. **Hash Maps**: Using `AutoHashMap` for all lookups (O(1) performance)
3. **Lazy Loading**: NFC data is loaded on demand when needed
4. **Reference Compliance**: Following the JavaScript implementation's logic exactly

## Critical Requirements

1. **Must match reference implementations exactly**
2. **Must handle all Unicode normalization cases**
3. **Must create NFC tokens only when codepoints change**
4. **Must integrate seamlessly with existing tokenization**

## Next Actions

1. Research available Zig Unicode libraries
2. Study the nf.json format
3. Create minimal test cases
4. Implement basic NFC checking
5. Verify against reference tests