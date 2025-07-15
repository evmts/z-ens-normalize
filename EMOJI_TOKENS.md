# Emoji Token Implementation Plan

## Overview

Emoji tokens are a special type of token in ENS normalization that handle emoji sequences. These sequences can be complex, involving base emojis, skin tone modifiers, zero-width joiners (ZWJ), and variation selectors (FE0F).

## Current Status

- ✅ Token type for emoji exists (`tokenizer.TokenType.emoji`)
- ✅ Data structure for emoji tokens exists
- ❌ Emoji parsing not implemented
- ❌ Emoji validation not implemented
- ❌ Emoji data not loaded from spec.json

## Reference Implementation Analysis

### JavaScript (ens-normalize.js)

```javascript
// From tokenizer - emoji regex building
function build_emoji_regex(emoji) {
    // Creates a regex that matches all valid emoji sequences
    let union = emoji.map(e => e.cps.map(cp => quote_cp(cp)).join('')).join('|');
    return new RegExp(`(${union})`, 'gu');
}

// Token structure for emoji
{
    type: TY_EMOJI,
    input: "👨🏻", // original input string
    cps: [128104, 127995], // input codepoints
    emoji: [128104, 127995], // normalized emoji codepoints
}

// From lib.js - emoji processing
function process_emoji(cps, emoji) {
    let v = cps.slice();
    if (v.length > 0 && v[0] == 0xFE0F) v.shift(); // drop leading FE0F
    if (v.length > 0 && v[v.length-1] == 0xFE0F) v.pop(); // drop trailing FE0F
    return emoji.find(e => compare_arrays(e, v)) || cps;
}

// Validation rules
if (token.type === TY_EMOJI) {
    if (emoji_disabled) throw error_disallowed(token); 
    let {emoji: cps} = token;
    if (chunk.some(g => !g.V.has(cps))) {
        throw error_group_member(groups[0], cps);
    }
}
```

### Rust (ens-normalize-rs)

```rust
// From tokens/types.rs
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TokenEmoji {
    pub input: String,           // original input substring
    pub cps_input: Vec<CodePoint>, // input codepoints
    pub emoji: Vec<CodePoint>,   // normalized emoji (with FE0F)
    pub cps_no_fe0f: Vec<CodePoint>, // emoji without FE0F
}

// From tokenize.rs - emoji detection
fn maybe_starts_with_emoji(
    i: usize,
    label: &str,
    emojis: &[regex::Match],
    specs: &CodePointsSpecs,
) -> Option<TokenEmoji> {
    emojis.iter().find_map(|emoji| {
        let start = emoji.start();
        if start == i {
            let end = emoji.end();
            let input_cps = utils::str2cps(&label[start..end]);
            let cps_no_fe0f = utils::filter_fe0f(&input_cps);
            let emoji = specs
                .cps_emoji_no_fe0f_to_pretty(&cps_no_fe0f)
                .expect("emoji should be found")
                .clone();
            Some(TokenEmoji {
                input: label[start..end].to_string(),
                cps_input: input_cps,
                emoji,
                cps_no_fe0f,
            })
        } else {
            None
        }
    })
}

// Emoji regex pattern
pub fn build_emoji_regex(&self) -> Regex {
    let pattern = self.emojis
        .iter()
        .map(|e| {
            e.no_fe0f.iter()
                .map(|&cp| regex::escape(&char::from_u32(cp).unwrap().to_string()))
                .collect::<String>()
        })
        .collect::<Vec<_>>()
        .join("|");
    Regex::new(&format!("({})", pattern)).unwrap()
}
```

### Go (go-ens-normalize)

```go
// From emojis.go
type Emoji struct {
    Emoji []rune // the canonical emoji sequence (with FE0F)
    NoFE0F []rune // emoji without FE0F for matching
}

func (n *Normalizer) findEmoji(runes []rune) (*Emoji, int) {
    // Try to match longest emoji first
    for l := min(len(runes), n.maxEmojiLength); l > 0; l-- {
        candidate := runes[:l]
        candidateNoFE0F := filterFE0F(candidate)
        
        if emoji, found := n.emojiMap[string(candidateNoFE0F)]; found {
            return emoji, l
        }
    }
    return nil, 0
}

// Validation
func (n *Normalizer) validateEmoji(emoji *Emoji, groups []*Group) error {
    if n.emojiDisabled {
        return &EmojiDisabledError{Emoji: emoji.Emoji}
    }
    
    // Check if emoji is valid in all groups
    for _, g := range groups {
        if !g.ContainsEmoji(emoji.Emoji) {
            return &InvalidEmojiError{Emoji: emoji.Emoji, Group: g}
        }
    }
    
    return nil
}
```

### Java (ENSNormalize.java)

```java
// From EmojiSequence.java
public class EmojiSequence {
    private final IntList emoji; // canonical form with FE0F
    private final IntList withoutFE0F; // for matching
    
    public static EmojiSequence parse(IntList cps) {
        IntList withoutFE0F = filterFE0F(cps);
        return EMOJI_MAP.get(withoutFE0F);
    }
    
    private static IntList filterFE0F(IntList cps) {
        IntList result = new IntArrayList();
        for (int cp : cps) {
            if (cp != 0xFE0F) {
                result.add(cp);
            }
        }
        return result;
    }
}

// From tokenize - emoji regex
private static Pattern buildEmojiPattern() {
    String pattern = EMOJIS.stream()
        .map(e -> e.getWithoutFE0F().stream()
            .map(cp -> Pattern.quote(new String(Character.toChars(cp))))
            .collect(Collectors.joining()))
        .collect(Collectors.joining("|"));
    return Pattern.compile("(" + pattern + ")");
}
```

### C# (ENSNormalize.cs)

```csharp
// From EmojiSequence.cs
public class EmojiSequence
{
    public IList<int> Emoji { get; } // canonical form
    public IList<int> WithoutFE0F { get; } // for matching
    
    public static EmojiSequence? Find(IList<int> cps)
    {
        var withoutFE0F = FilterFE0F(cps);
        return EmojiMap.TryGetValue(withoutFE0F, out var emoji) ? emoji : null;
    }
    
    private static IList<int> FilterFE0F(IList<int> cps)
    {
        return cps.Where(cp => cp != 0xFE0F).ToList();
    }
}

// Validation
if (!group.ValidEmojis.Contains(emoji))
{
    throw new InvalidLabelException($"emoji not allowed in group {group.Name}");
}
```

## Key Observations

1. **FE0F Handling**: All implementations filter out FE0F (variation selector) for matching, but keep the canonical form with FE0F
2. **Longest Match First**: Implementations try to match the longest possible emoji sequence
3. **Data Structure**: Two forms stored - one with FE0F (canonical) and one without (for matching)
4. **Regex Pattern**: Built from all valid emoji sequences without FE0F
5. **Group Validation**: Emojis must be valid in all script groups of a label

## Emoji Data Format in spec.json

```json
{
  "emoji": [
    [[128104, 127995], [128104, 127995]], // [no_fe0f, canonical]
    [[128105, 8205, 9877, 65039], [128105, 8205, 9877, 65039]],
    // ... more emoji sequences
  ]
}
```

## Test Cases from References

### JavaScript Tests

```javascript
// Basic emoji
{ input: "👍", expected: "👍" }

// Emoji with skin tone
{ input: "👍🏻", expected: "👍🏻" }

// ZWJ sequence
{ input: "👨‍👩‍👧‍👦", expected: "👨‍👩‍👧‍👦" }

// Emoji with FE0F variations
{ input: "☺️", expected: "☺️" } // with FE0F
{ input: "☺", expected: "☺️" }  // without FE0F normalizes to with

// Mixed emoji and text
{ input: "hello👋world", expected: "hello👋world" }
```

### Rust Tests

```rust
#[test]
fn test_emoji_parsing() {
    let input = "test👨‍👩‍👧‍👦emoji";
    let tokens = tokenize(input);
    
    assert!(tokens.iter().any(|t| matches!(t, Token::Emoji(_))));
}

#[test]
fn test_emoji_fe0f_normalization() {
    // Input without FE0F should match emoji with FE0F
    let input1 = "☺"; // U+263A
    let input2 = "☺️"; // U+263A U+FE0F
    
    let tokens1 = tokenize(input1);
    let tokens2 = tokenize(input2);
    
    // Both should produce the same emoji token
    assert_eq!(tokens1, tokens2);
}
```

## Implementation Strategy for Zig

### 1. Data Structures
```zig
pub const EmojiData = struct {
    emoji: []const CodePoint,      // canonical form (with FE0F)
    no_fe0f: []const CodePoint,    // for matching (without FE0F)
};

pub const EmojiMap = struct {
    // Map from no_fe0f string to EmojiData
    emojis: std.StringHashMap(EmojiData),
    // Maximum emoji length for optimization
    max_length: usize,
    allocator: std.mem.Allocator,
};
```

### 2. Loading from spec.json
```zig
pub fn loadEmojiData(allocator: std.mem.Allocator) !EmojiMap {
    // Load emoji array from spec.json
    // Build hash map for fast lookup
    // Track maximum length
}
```

### 3. Emoji Detection
```zig
fn findEmojiAt(input: []const u8, pos: usize, emoji_map: *const EmojiMap) ?EmojiMatch {
    // Try longest match first
    // Convert to codepoints
    // Remove FE0F
    // Look up in map
    // Return match with length
}
```

### 4. Token Creation
```zig
pub fn createEmoji(allocator: std.mem.Allocator, input: []const u8, emoji_data: EmojiData) !Token {
    return Token{
        .type = .emoji,
        .data = .{ .emoji = .{
            .input = try allocator.dupe(u8, input),
            .cps_input = try utils.str2cps(allocator, input),
            .emoji = try allocator.dupe(CodePoint, emoji_data.emoji),
            .cps_no_fe0f = try allocator.dupe(CodePoint, emoji_data.no_fe0f),
        }},
        .allocator = allocator,
    };
}
```

## Invariants and Fuzz Testing

### Invariants
1. **FE0F Normalization**: Any emoji sequence with/without FE0F should produce the same token
2. **Longest Match**: Always match the longest valid emoji sequence
3. **No Overlaps**: Emoji tokens should not overlap with other tokens
4. **Valid Sequences Only**: Only sequences in spec.json are valid emojis

### Fuzz Testing Strategy
```zig
test "fuzz emoji parsing" {
    // Generate random unicode sequences
    // Mix valid emojis with invalid sequences
    // Verify:
    // 1. Valid emojis are always recognized
    // 2. Invalid sequences are not treated as emojis
    // 3. FE0F variations are normalized correctly
    // 4. ZWJ sequences are handled properly
}
```

## Complex Cases to Handle

1. **Skin Tone Modifiers**: Base emoji + skin tone modifier (U+1F3FB-1F3FF)
2. **ZWJ Sequences**: Multiple emojis joined with Zero Width Joiner (U+200D)
3. **Regional Indicators**: Flag emojis made from pairs of regional indicator symbols
4. **Keycap Sequences**: Digit/symbol + FE0F + 20E3
5. **Tag Sequences**: Base emoji + tag characters (rarely used)

## Next Steps

1. Load emoji data from spec.json
2. Build emoji lookup map (no_fe0f -> emoji data)
3. Implement emoji detection in tokenizer
4. Create emoji tokens with proper data
5. Add validation for emoji in script groups
6. Handle FE0F normalization
7. Add comprehensive tests