# JavaScript vs Zig ENS Normalization Implementation Comparison

## Major Unimplemented Features in Zig

### 1. **ens_normalize_fragment() Function**
**JS Implementation (src/lib.js:287-291):**
- Processes fragments without full label validation
- Splits on STOP character and applies normalization
- Used for partial normalization scenarios

**Zig Status:** ❌ Not implemented

### 2. **ens_split() Function**
**JS Implementation (src/lib.js:329-331):**
- Splits name into labels with detailed information
- Returns array of label objects with metadata (input, offset, tokens, type, error)
- Preserves emoji optionally

**Zig Status:** ❌ Not implemented

### 3. **ens_tokenize() Function with Options**
**JS Implementation (src/lib.js:674-750):**
- Returns detailed token information with types
- Supports `nf` option to collapse unnormalized runs
- Provides token metadata (type, cp, cps, input, etc.)

**Zig Status:** ⚠️ Partially implemented
- Basic tokenization exists but lacks detailed token metadata
- No options parameter support

### 4. **Beautify Greek Character Transformation**
**JS Implementation (src/lib.js:319):**
```javascript
// update ethereum symbol: ξ => Ξ if not greek
if (type !== 'Greek') array_replace(output, 0x3BE, 0x39E);
```

**Zig Status:** ❌ Not implemented in beautify function

### 5. **Label Type Detection**
**JS Implementation:**
- Detects: ASCII, Emoji, Greek, and specific script types (Latin, Japanese, etc.)
- Returns restricted group information (e.g., "Restricted[Latin]")

**Zig Status:** ⚠️ Basic implementation only
- Only detects ASCII, Emoji, and "Unicode" (generic)
- No script-specific detection

### 6. **Whole Confusable Detection**
**JS Implementation (src/lib.js:405-429):**
- Complex algorithm for detecting whole-script confusables
- Uses WHOLE_MAP and WHOLE_VALID sets
- Checks confusable intersections across groups

**Zig Status:** ❌ Not implemented

### 7. **Mixed Script Detection**
**JS Implementation (src/lib.js:432-459):**
- Determines which script group(s) contain all characters
- Throws specific errors for illegal mixtures
- Handles character decomposition validation

**Zig Status:** ❌ Not implemented

### 8. **NSM (Non-Spacing Mark) Validation**
**JS Implementation (src/lib.js:510-545):**
- Limits to NSM_MAX (4) consecutive non-spacing marks
- Forbids duplicate non-spacing marks in sequence
- Special handling for whitelisted groups

**Zig Status:** ⚠️ File exists but not integrated into validation

### 9. **Label Extension Check (xn--)**
**JS Implementation (src/lib.js:207-211):**
```javascript
function check_label_extension(cps) {
    if (cps.length >= 4 && cps[2] == HYPHEN && cps[3] == HYPHEN) {
        throw new Error(`invalid label extension: "${str_from_cps(cps.slice(0, 4))}"`);
    }
}
```

**Zig Status:** ⚠️ Basic check exists but not complete

### 10. **Emoji Sequence Validation**
**JS Implementation (src/lib.js:168-191):**
- Validates proper FE0F placement in emoji sequences
- Builds emoji trie for efficient matching
- Handles complex emoji sequences

**Zig Status:** ⚠️ Basic emoji detection but no sequence validation

## Major Bugs and Differences

### 1. **Token Collapse Logic**
**Issue:** Zig collapses all consecutive valid tokens, JS has more nuanced approach with NFC checking

### 2. **Error Types**
**JS:** Detailed error messages with context
**Zig:** Generic error types without detailed messages

### 3. **Character Classification Priority**
**JS Order:**
1. Emoji (highest priority)
2. STOP
3. VALID
4. MAPPED  
5. IGNORED
6. Disallowed

**Zig:** Different ordering, emoji not given highest priority in all cases

### 4. **NFC Application**
**JS:** Selective NFC based on NFC_CHECK set
**Zig:** Applies NFC more broadly without selective checking

### 5. **Empty Label Handling**
**JS:** Throws specific "empty label" error
**Zig:** Generic DisallowedSequence error

## Critical Missing Components

1. **Fenced Character Validation** - Stub implementation only
2. **Combining Mark Rules** - File exists but not integrated
3. **Script Group Validation** - Commented out due to errors
4. **Confusable Detection** - Data loaded but not used
5. **Bidi Text Handling** - No implementation
6. **Safe String Generation** - No equivalent to safe_str_from_cps()

## Recommendations

1. **Immediate Priority:**
   - Implement proper label splitting on STOP characters
   - Add script group detection and validation
   - Integrate NSM validation rules
   - Fix emoji priority in tokenization

2. **High Priority:**
   - Implement whole confusable detection
   - Add mixed script validation
   - Implement ens_split() for proper label metadata
   - Add detailed error messages

3. **Medium Priority:**
   - Implement ens_normalize_fragment()
   - Add Greek character beautification
   - Implement fenced character validation
   - Add bidi text support

4. **Testing Gaps:**
   - No tests for multi-label names (with dots)
   - No tests for script mixing errors
   - No tests for confusable detection
   - No tests for complex emoji sequences