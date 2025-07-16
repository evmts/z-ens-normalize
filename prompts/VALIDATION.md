# ENS Validation Implementation

## Overview

Validation is the critical security component in the ENS normalization pipeline that occurs after tokenization. It ensures that domain names comply with ENSIP-15 specifications and prevents homograph attacks through comprehensive character and script validation.

## What Validation Does

The validation process performs several critical security checks:

1. **Structural Validation**: Ensures labels aren't empty and have valid structure
2. **Character Placement Rules**: Validates underscore, hyphen, and fenced character placement
3. **Script Group Detection**: Identifies which Unicode script group each label belongs to
4. **Confusable Prevention**: Prevents mixing of visually similar characters from different scripts
5. **Combining Mark Validation**: Ensures proper combining mark placement and limits
6. **Non-Spacing Mark (NSM) Validation**: Prevents duplicate and excessive non-spacing marks
7. **Security Enforcement**: Blocks homograph attacks and domain spoofing attempts

## Validation Pipeline

```
TokenizedName → Validation → ValidatedName
    ↓
1. Empty label check
2. Leading underscore check  
3. Label extension check (ASCII)
4. Script detection (ASCII/Emoji/Unicode)
5. Combining mark validation
6. Fenced character validation
7. Group determination
8. Confusable detection
9. NSM validation
    ↓
ValidatedName (with script group)
```

## Reference Implementations

### JavaScript Implementation (Primary Reference)

**File**: `ens-normalize.js/src/lib.js`

```javascript
function checkValidLabel(cps, tokens) {
    if (norm.length == 0) throw new Error(`empty label`);
    checkLeadingUnderscore(norm);
    
    let emoji = tokens.some(x => x.is_emoji);
    if (!emoji && norm.every(cp => cp < 0x80)) { // ASCII
        checkLabelExtension(norm);
        return 'ASCII';
    }
    
    let chars = tokens.flatMap(x => x.is_emoji ? [] : x);
    if (!chars.length) return 'Emoji';
    
    if (CM.has(norm[0])) throw error_placement('leading combining mark');
    checkCombiningMarks(tokens);
    checkFenced(norm);
    
    let unique = Array.from(new Set(chars));
    let [g] = determineGroup(unique);
    checkGroup(g, chars);
    checkWhole(g, unique);
    return g.N;
}

// Leading underscore validation
function checkLeadingUnderscore(cps) {
    for (let i = 1; i < cps.length; i++) {
        if (cps[i] == 0x5F) {
            throw error_placement('underscore allowed only at start');
        }
    }
}

// Label extension validation (ASCII only)
function checkLabelExtension(cps) {
    if (cps.length >= 4 && cps[2] == 0x2D && cps[3] == 0x2D) {
        throw new Error('invalid label extension');
    }
}

// Fenced character validation
function checkFenced(cps) {
    let cp = cps[0];
    let prev = FENCED.get(cp);
    if (prev) throw error_placement(`leading ${prev}`);
    
    let n = cps.length;
    let last = -1;
    for (let i = 1; i < n; i++) {
        cp = cps[i];
        let match = FENCED.get(cp);
        if (match) {
            if (last == i) throw error_placement(`${prev} + ${match}`);
            last = i + 1;
            prev = match;
        }
    }
    if (last == n) throw error_placement(`trailing ${prev}`);
}

// Group determination
function determineGroup(unique) {
    let groups = GROUPS;
    for (let cp of unique) {
        let gs = groups.filter(g => group_has_cp(g, cp));
        if (!gs.length) {
            if (!GROUPS.some(g => group_has_cp(g, cp))) {
                throw error_disallowed(cp);
            } else {
                throw error_group_member(groups[0], cp);
            }
        }
        groups = gs;
        if (gs.length == 1) break;
    }
    return groups;
}

// Confusable detection
function checkWhole(group, unique) {
    let maker;
    let shared = [];
    for (let cp of unique) {
        let whole = WHOLE_MAP.get(cp);
        if (whole === UNIQUE_PH) return; // unique, non-confusable
        if (whole) {
            let set = whole.M.get(cp);
            maker = maker ? maker.filter(g => set.has(g)) : Array.from(set);
            if (!maker.length) return;
        } else {
            shared.push(cp);
        }
    }
    if (maker) {
        for (let g of maker) {
            if (shared.every(cp => group_has_cp(g, cp))) {
                throw new Error(`whole-script confusable: ${group.N}/${g.N}`);
            }
        }
    }
}
```

### Rust Implementation (Current)

**File**: `src/validate.rs`

```rust
pub fn validate_label(
    label: TokenizedLabel<'_>,
    specs: &CodePointsSpecs,
) -> Result<ValidatedLabel, ProcessError> {
    let norm = label.normalized();
    
    // Check if label is empty
    if norm.is_empty() {
        return Err(ProcessError::Confused("empty label".to_string()));
    }
    
    // Check for leading underscore
    if let Some(first_cp) = norm.first() {
        if *first_cp == constants::CP_UNDERSCORE {
            // Check for non-leading underscores
            if norm.iter().skip(1).any(|&cp| cp == constants::CP_UNDERSCORE) {
                return Err(ProcessError::CurrableError {
                    inner: CurrableError::UnderscoreInMiddle,
                    index: 0,
                    sequence: String::new(),
                    maybe_suggest: None,
                });
            }
        }
    }
    
    // Check for ASCII label extension
    if norm.len() >= 4 && norm[2] == constants::CP_HYPHEN && norm[3] == constants::CP_HYPHEN {
        return Err(ProcessError::CurrableError {
            inner: CurrableError::HyphenAtSecondAndThird,
            index: 2,
            sequence: String::new(),
            maybe_suggest: None,
        });
    }
    
    // Determine group and validate
    let group = checkAndGetGroup(allocator, label, specs)?;
    
    Ok(ValidatedLabel {
        original: label,
        group,
    })
}

fn checkAndGetGroup(
    allocator: std.mem.Allocator,
    label: TokenizedLabel,
    specs: *const code_points.CodePointsSpecs,
) !*const code_points.ParsedGroup {
    // TODO: implement group determination
    return error_types.ProcessError.Confused;
}
```

### Go Implementation

**File**: `go-ens-normalize/ensip15/ensip15.go`

```go
func (l *ENSIP15) checkValidLabel(cps []rune, tokens []OutputToken) (*Group, error) {
    if len(cps) == 0 {
        return nil, ErrEmptyLabel
    }
    
    // Check for leading underscore
    if err := l.checkLeadingUnderscore(cps); err != nil {
        return nil, err
    }
    
    // ASCII label extension check
    if isASCII(cps) {
        if err := l.checkLabelExtension(cps); err != nil {
            return nil, err
        }
        return l.asciiGroup, nil
    }
    
    // Check for emoji-only labels
    if isEmojiOnly(tokens) {
        return l.emojiGroup, nil
    }
    
    // Combining mark validation
    if err := l.checkCombiningMarks(cps); err != nil {
        return nil, err
    }
    
    // Fenced character validation
    if err := l.checkFenced(cps); err != nil {
        return nil, err
    }
    
    // Group determination
    group, err := l.determineGroup(cps)
    if err != nil {
        return nil, err
    }
    
    // Confusable detection
    if err := l.checkWhole(group, cps); err != nil {
        return nil, err
    }
    
    return group, nil
}

func (l *ENSIP15) checkLeadingUnderscore(cps []rune) error {
    for i := 1; i < len(cps); i++ {
        if cps[i] == '_' {
            return ErrLeadingUnderscore
        }
    }
    return nil
}

func (l *ENSIP15) checkLabelExtension(cps []rune) error {
    if len(cps) >= 4 && cps[2] == '-' && cps[3] == '-' {
        return ErrInvalidLabelExtension
    }
    return nil
}

func (l *ENSIP15) checkFenced(cps []rune) error {
    if len(cps) == 0 {
        return nil
    }
    
    // Check leading fenced
    if l.fenced.Has(cps[0]) {
        return ErrFencedLeading
    }
    
    // Check trailing fenced
    if l.fenced.Has(cps[len(cps)-1]) {
        return ErrFencedTrailing
    }
    
    // Check adjacent fenced
    prev := false
    for _, cp := range cps {
        if l.fenced.Has(cp) {
            if prev {
                return ErrFencedAdjacent
            }
            prev = true
        } else {
            prev = false
        }
    }
    
    return nil
}

func (l *ENSIP15) checkGroup(group *Group, cps []rune) error {
    for _, cp := range cps {
        if !group.Contains(cp) {
            return l.createMixtureError(group, cp)
        }
    }
    
    if !group.cmWhitelisted {
        // NSM validation logic
        decomposed := l.nf.NFD(cps)
        nsm_count := 0
        var prev_nsm rune
        
        for i := 1; i < len(decomposed); i++ {
            if l.nonSpacingMarks.Contains(decomposed[i]) {
                nsm_count++
                if nsm_count > 4 {
                    return ErrNSMExcessive
                }
                if decomposed[i] == prev_nsm {
                    return ErrNSMDuplicate
                }
                prev_nsm = decomposed[i]
            } else {
                nsm_count = 0
                prev_nsm = 0
            }
        }
    }
    
    return nil
}
```

### C# Implementation

**File**: `ENSNormalize.cs/ENSNormalize/ENSIP15.cs`

```csharp
public ValidationResult ValidateLabel(string label, List<OutputToken> tokens)
{
    if (string.IsNullOrEmpty(label))
        throw new InvalidLabelException("Empty label");
    
    var codepoints = label.EnumerateRunes().Select(r => r.Value).ToArray();
    
    // Check leading underscore
    CheckLeadingUnderscore(codepoints);
    
    // ASCII label extension check
    if (IsASCII(codepoints))
    {
        CheckLabelExtension(codepoints);
        return new ValidationResult { Group = "ASCII" };
    }
    
    // Emoji-only check
    if (IsEmojiOnly(tokens))
    {
        return new ValidationResult { Group = "Emoji" };
    }
    
    // Combining mark validation
    CheckCombiningMarks(codepoints);
    
    // Fenced character validation
    CheckFenced(codepoints);
    
    // Group determination
    var group = DetermineGroup(codepoints);
    
    // Confusable detection
    CheckWhole(group, codepoints);
    
    return new ValidationResult { Group = group.Name };
}

private void CheckLeadingUnderscore(int[] codepoints)
{
    for (int i = 1; i < codepoints.Length; i++)
    {
        if (codepoints[i] == '_')
        {
            throw new InvalidLabelException("Underscore allowed only at start");
        }
    }
}

private void CheckFenced(int[] codepoints)
{
    if (codepoints.Length == 0) return;
    
    if (_fenced.Contains(codepoints[0]))
        throw new InvalidLabelException("Leading fenced character");
    
    if (_fenced.Contains(codepoints[codepoints.Length - 1]))
        throw new InvalidLabelException("Trailing fenced character");
    
    bool prevFenced = false;
    foreach (var cp in codepoints)
    {
        if (_fenced.Contains(cp))
        {
            if (prevFenced)
                throw new InvalidLabelException("Adjacent fenced characters");
            prevFenced = true;
        }
        else
        {
            prevFenced = false;
        }
    }
}
```

### Java Implementation

**File**: `ENSNormalize.java/lib/src/main/java/io/github/adraffy/ens/ENSIP15.java`

```java
public ValidationResult validateLabel(String label, List<OutputToken> tokens) {
    int[] codepoints = label.codePoints().toArray();
    
    if (codepoints.length == 0) {
        throw new InvalidLabelException("Empty label");
    }
    
    // Check leading underscore
    checkLeadingUnderscore(codepoints);
    
    // ASCII label extension check
    if (isASCII(codepoints)) {
        checkLabelExtension(codepoints);
        return new ValidationResult("ASCII");
    }
    
    // Emoji-only check
    if (isEmojiOnly(tokens)) {
        return new ValidationResult("Emoji");
    }
    
    // Combining mark validation
    checkCombiningMarks(codepoints);
    
    // Fenced character validation
    checkFenced(codepoints);
    
    // Group determination
    Group group = determineGroup(codepoints);
    
    // Confusable detection
    checkWhole(group, codepoints);
    
    return new ValidationResult(group.name);
}

private void checkLeadingUnderscore(int[] codepoints) {
    for (int i = 1; i < codepoints.length; i++) {
        if (codepoints[i] == '_') {
            throw new InvalidLabelException("Underscore allowed only at start");
        }
    }
}

private void checkLabelExtension(int[] codepoints) {
    if (codepoints.length >= 4 && codepoints[2] == '-' && codepoints[3] == '-') {
        throw new InvalidLabelException("Invalid label extension");
    }
}

private void checkFenced(int[] codepoints) {
    if (codepoints.length == 0) return;
    
    if (fenced.contains(codepoints[0])) {
        throw new InvalidLabelException("Leading fenced character");
    }
    
    if (fenced.contains(codepoints[codepoints.length - 1])) {
        throw new InvalidLabelException("Trailing fenced character");
    }
    
    boolean prevFenced = false;
    for (int cp : codepoints) {
        if (fenced.contains(cp)) {
            if (prevFenced) {
                throw new InvalidLabelException("Adjacent fenced characters");
            }
            prevFenced = true;
        } else {
            prevFenced = false;
        }
    }
}
```

### Python Implementation

**File**: `ens-normalize-python/ens_normalize/normalization.py`

```python
def validate_label(label: str, tokens: List[Token], spec: NormalizationSpec) -> ValidationResult:
    codepoints = [ord(c) for c in label]
    
    if not codepoints:
        raise InvalidLabelException("Empty label")
    
    # Check leading underscore
    check_leading_underscore(codepoints)
    
    # ASCII label extension check
    if is_ascii(codepoints):
        check_label_extension(codepoints)
        return ValidationResult(group="ASCII")
    
    # Emoji-only check
    if is_emoji_only(tokens):
        return ValidationResult(group="Emoji")
    
    # Combining mark validation
    check_combining_marks(codepoints)
    
    # Fenced character validation
    check_fenced(codepoints, spec)
    
    # Group determination
    group = determine_group(codepoints, spec)
    
    # Confusable detection
    check_whole(group, codepoints, spec)
    
    return ValidationResult(group=group.name)

def check_leading_underscore(codepoints: List[int]) -> None:
    for i in range(1, len(codepoints)):
        if codepoints[i] == ord('_'):
            raise InvalidLabelException("Underscore allowed only at start")

def check_fenced(codepoints: List[int], spec: NormalizationSpec) -> None:
    if not codepoints:
        return
    
    if codepoints[0] in spec.fenced:
        raise InvalidLabelException("Leading fenced character")
    
    if codepoints[-1] in spec.fenced:
        raise InvalidLabelException("Trailing fenced character")
    
    prev_fenced = False
    for cp in codepoints:
        if cp in spec.fenced:
            if prev_fenced:
                raise InvalidLabelException("Adjacent fenced characters")
            prev_fenced = True
        else:
            prev_fenced = False
```

## Test Cases

### Basic Validation Tests

```javascript
// Empty label tests
const EMPTY_TESTS = [
    {name: "", error: true, comment: "Empty"},
    {name: " ", error: true, comment: "Empty: Whitespace"},
    {name: "️", error: true, comment: "Empty: Ignorable"},
    {name: ".", error: true, comment: "Null Labels"},
];

// Valid basic tests
const BASIC_TESTS = [
    {name: "vitalik.eth", comment: "Trivial Name"},
    {name: "123.eth", comment: "Trivial Digit Name"},
    {name: "a", comment: "Single Character"},
    {name: "ab", comment: "Two Characters"},
];
```

### Underscore Rule Tests

```javascript
const UNDERSCORE_TESTS = [
    {name: "_a", comment: "Leading Underscore"},
    {name: "_____a", comment: "Multiple Leading Underscores"},
    {name: "a_b", error: true, comment: "Non-leading Underscore"},
    {name: "a_", error: true, comment: "Trailing Underscore"},
    {name: "_a_b", error: true, comment: "Leading + Non-leading Underscore"},
];
```

### Hyphen Rule Tests (ASCII Label Extension)

```javascript
const HYPHEN_TESTS = [
    {name: "ab-c", comment: "Valid hyphen"},
    {name: "-abc", comment: "Leading hyphen"},
    {name: "abc-", comment: "Trailing hyphen"},
    {name: "te--st", error: true, comment: "CheckHyphens, Section 4.1 Rule #2 (ASCII)"},
    {name: "xn--test", error: true, comment: "ASCII label extension"},
    {name: "xn--💩", comment: "CheckHyphens, Section 4.1 Rule #2 (Unicode)"},
];
```

### Fenced Character Tests

```javascript
const FENCED_TESTS = [
    // Apostrophe tests
    {name: "'a", error: true, comment: "Apostrophe: leading"},
    {name: "a'", error: true, comment: "Apostrophe: trailing"},
    {name: "a''a", error: true, comment: "Apostrophe: adjacent"},
    {name: "a'a'a", norm: "a'a'a", comment: "Apostrophe: valid spacing"},
    
    // Middle dot tests
    {name: "·a", error: true, comment: "Middle dot: leading"},
    {name: "a·", error: true, comment: "Middle dot: trailing"},
    {name: "a··a", error: true, comment: "Middle dot: adjacent"},
    {name: "a·a·a", comment: "Middle dot: valid spacing"},
    
    // Fraction slash tests
    {name: "⁄a", error: true, comment: "Fraction slash: leading"},
    {name: "a⁄", error: true, comment: "Fraction slash: trailing"},
    {name: "a⁄⁄a", error: true, comment: "Fraction slash: adjacent"},
    {name: "1⁄2", comment: "Fraction slash: valid usage"},
];
```

### Combining Mark Tests

```javascript
const COMBINING_MARK_TESTS = [
    {name: "̃", error: true, comment: "Leading CM"},
    {name: "💩̃", error: true, comment: "Emoji + CM"},
    {name: "ã", comment: "Valid CM"},
    {name: "café", comment: "Composed character"},
    {name: "cafe\u0301", comment: "Decomposed character"},
];
```

### Non-Spacing Mark (NSM) Tests

```javascript
const NSM_TESTS = [
    {name: "آٍٍ", error: true, comment: "NSM: repeated w/NFD expansion"},
    {name: "إؐؑؒ", comment: "NSM: at max (4)"},
    {name: "إؐؑؒؓ", error: true, comment: "NSM: too many (5/4)"},
    {name: "إؐؑؒؓؔ", error: true, comment: "NSM: too many (6/4)"},
];
```

### Confusable Tests

```javascript
const CONFUSABLE_TESTS = [
    {name: "0х", error: true, comment: "confuse: Cyrillic x"},
    {name: "0x", comment: "confuse: Latin x"},
    {name: "½", norm: "1⁄2", comment: "confuse: fraction mapping"},
    {name: "ℌ", norm: "H", comment: "confuse: script H"},
    {name: "𝒽", norm: "h", comment: "confuse: script h"},
];
```

### Script Group Tests

```javascript
const SCRIPT_GROUP_TESTS = [
    {name: "hello", group: "Latin", comment: "Latin script"},
    {name: "привет", group: "Cyrillic", comment: "Cyrillic script"},
    {name: "γεια", group: "Greek", comment: "Greek script"},
    {name: "שלום", group: "Hebrew", comment: "Hebrew script"},
    {name: "مرحبا", group: "Arabic", comment: "Arabic script"},
    {name: "你好", group: "Han", comment: "Han script"},
    {name: "こんにちは", group: "Hiragana", comment: "Hiragana script"},
    {name: "안녕", group: "Hangul", comment: "Hangul script"},
];
```

### Mixed Script Tests (Should Fail)

```javascript
const MIXED_SCRIPT_TESTS = [
    {name: "helloпривет", error: true, comment: "Latin + Cyrillic"},
    {name: "test测试", error: true, comment: "Latin + Han"},
    {name: "café中文", error: true, comment: "Latin + Han"},
    {name: "混合script", error: true, comment: "Han + Latin"},
];
```

## Error Handling

### Error Types

```rust
pub enum ValidationError {
    EmptyLabel,
    InvalidLabelExtension,
    UnderscoreInMiddle,
    LeadingCombiningMark,
    CombiningMarkAfterEmoji,
    FencedLeading(char),
    FencedTrailing(char),
    FencedAdjacent(char, char),
    DisallowedCharacter(u32),
    IllegalMixture(String, String),
    WholeScriptConfusable(String, String),
    DuplicateNSM(u32),
    ExcessiveNSM(usize),
}
```

### Error Messages

```rust
impl ValidationError {
    pub fn message(&self) -> String {
        match self {
            ValidationError::EmptyLabel => "Empty label".to_string(),
            ValidationError::InvalidLabelExtension => "Invalid label extension".to_string(),
            ValidationError::UnderscoreInMiddle => "Underscore allowed only at start".to_string(),
            ValidationError::LeadingCombiningMark => "Leading combining mark".to_string(),
            ValidationError::CombiningMarkAfterEmoji => "Combining mark after emoji".to_string(),
            ValidationError::FencedLeading(c) => format!("Leading fenced character: {}", c),
            ValidationError::FencedTrailing(c) => format!("Trailing fenced character: {}", c),
            ValidationError::FencedAdjacent(c1, c2) => format!("Adjacent fenced characters: {} + {}", c1, c2),
            ValidationError::DisallowedCharacter(cp) => format!("Disallowed character: U+{:04X}", cp),
            ValidationError::IllegalMixture(g1, g2) => format!("Illegal mixture: {} + {}", g1, g2),
            ValidationError::WholeScriptConfusable(g1, g2) => format!("Whole-script confusable: {} / {}", g1, g2),
            ValidationError::DuplicateNSM(cp) => format!("Duplicate non-spacing mark: U+{:04X}", cp),
            ValidationError::ExcessiveNSM(count) => format!("Excessive non-spacing marks: {} (max 4)", count),
        }
    }
}
```

## Algorithm Analysis

The validation algorithm follows this pattern across all implementations:

1. **Structural Validation**: Check for empty labels and basic structure
2. **Character Rule Validation**: Apply character-specific placement rules
3. **Script Classification**: Determine if label is ASCII, Emoji, or Unicode script
4. **Unicode Validation**: For Unicode labels, perform comprehensive validation
5. **Security Checks**: Prevent homograph attacks through confusable detection

### Key Data Structures

- **Script Groups**: Unicode script classifications (Latin, Greek, Cyrillic, etc.)
- **Fenced Characters**: Characters with placement restrictions
- **Combining Marks**: Characters that modify base characters
- **Non-Spacing Marks**: Subset of combining marks with special rules
- **Confusable Maps**: Mappings between visually similar characters

### Performance Considerations

- **Character Classification**: Fast lookup tables for character properties
- **Script Detection**: Efficient group intersection algorithms
- **Confusable Checking**: Optimized whole-script confusable detection
- **Error Reporting**: Detailed error messages with context

## Zig Implementation Strategy

For the Zig implementation, we need to:

1. **Define Validation Types**: Create Zig equivalents of validation structures
2. **Implement Character Classification**: Build lookup tables for character properties
3. **Script Group Logic**: Implement script group detection and validation
4. **Error Handling**: Use Zig's error unions for validation errors
5. **Memory Management**: Use allocators for dynamic validation data
6. **Testing**: Port all validation test cases to Zig test format
7. **Fuzz Testing**: Add comprehensive fuzz testing for validation edge cases

## Fuzz Testing Strategy

### Fuzz Testing Categories

1. **Input Boundary Testing**
   - Empty strings and null inputs
   - Single character inputs
   - Maximum length inputs
   - Invalid UTF-8 sequences

2. **Character Placement Fuzzing**
   - Underscore placement variations
   - Hyphen positioning tests
   - Fenced character placement patterns
   - Combining mark positioning

3. **Script Mixing Fuzzing**
   - All possible script combinations
   - Gradual script transitions
   - Confusable character substitutions
   - Mixed emoji and text combinations

4. **NSM Fuzzing**
   - NSM count variations (1-10)
   - NSM duplication patterns
   - NSM positioning tests
   - Complex NSM sequences

5. **Edge Case Fuzzing**
   - Malformed emoji sequences
   - Invalid Unicode normalization
   - Boundary Unicode code points
   - Pathological confusable patterns

### Fuzz Test Implementation

```zig
// Example fuzz test structure
pub fn fuzz_validation(input: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Should never crash, even with malformed input
    const tokenized = tokenizer.TokenizedName.fromInput(
        allocator, 
        input, 
        &specs, 
        false
    ) catch |err| switch (err) {
        error.InvalidUtf8 => return,
        error.OutOfMemory => return,
        else => return err,
    };
    defer tokenized.deinit();
    
    // Validation should handle any tokenized input gracefully
    const validated = validator.validateLabel(
        allocator,
        tokenized,
        &specs
    ) catch |err| switch (err) {
        error.EmptyLabel => return,
        error.InvalidLabelExtension => return,
        error.UnderscoreInMiddle => return,
        error.LeadingCombiningMark => return,
        error.FencedLeading => return,
        error.FencedTrailing => return,
        error.FencedAdjacent => return,
        error.DisallowedCharacter => return,
        error.IllegalMixture => return,
        error.WholeScriptConfusable => return,
        error.DuplicateNSM => return,
        error.ExcessiveNSM => return,
        error.OutOfMemory => return,
        else => return err,
    };
    defer validated.deinit();
    
    // Validate that the result maintains invariants
    try validateValidationInvariants(validated);
}
```

### Specific Fuzz Scenarios

1. **Underscore Fuzzing**
   ```zig
   // Test underscore at every position
   for (0..name.len) |pos| {
       var test_name = name.clone();
       test_name[pos] = '_';
       try fuzz_validation(test_name);
   }
   ```

2. **Confusable Fuzzing**
   ```zig
   // Test confusable character substitutions
   const confusable_pairs = [_]struct{u32, u32}{
       .{0x0078, 0x0445}, // x, х (Latin, Cyrillic)
       .{0x006F, 0x043E}, // o, о (Latin, Cyrillic)
       .{0x0061, 0x0430}, // a, а (Latin, Cyrillic)
   };
   
   for (confusable_pairs) |pair| {
       // Generate mixed sequences
       var mixed = std.ArrayList(u32).init(allocator);
       mixed.append(pair[0]);
       mixed.append(pair[1]);
       try fuzz_validation(utf8FromCodepoints(mixed.items));
   }
   ```

3. **NSM Fuzzing**
   ```zig
   // Test NSM sequences
   const nsm_chars = [_]u32{0x0300, 0x0301, 0x0302, 0x0303};
   
   for (1..7) |count| {
       for ([_]bool{false, true}) |duplicate| {
           var sequence = std.ArrayList(u32).init(allocator);
           sequence.append(0x0061); // base character 'a'
           
           for (0..count) |i| {
               if (duplicate) {
                   sequence.append(nsm_chars[0]);
               } else {
                   sequence.append(nsm_chars[i % nsm_chars.len]);
               }
           }
           
           try fuzz_validation(utf8FromCodepoints(sequence.items));
       }
   }
   ```

This comprehensive validation implementation will provide robust security against homograph attacks and ensure complete ENSIP-15 compliance for the Zig ENS normalization system.