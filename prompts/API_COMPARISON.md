# ENS Normalize API Comparison

## JavaScript (ens-normalize.js by adraffy)

### Main Functions
```javascript
// Main normalization - throws on invalid names
ens_normalize(name: string) → string

// Beautify for display - throws on invalid names  
ens_beautify(name: string) → string

// Tokenize - never throws
ens_tokenize(name: string, options?: object) → Token[]

// Normalize fragment (handles partial names)
ens_normalize_fragment(frag: string, decompose?: boolean) → string

// Split into labels
ens_split(name: string, preserve_emoji?: boolean) → Label[]
```

### Error Handling
- Throws descriptive errors for invalid names
- All errors are safe to print (non-printable chars shown as {HEX})
- Specific error types for different validation failures

### Key Characteristics
- Simple string in/string out API
- Stateless functions (no normalizer object)
- Separate functions for different use cases
- Optional parameters for advanced features

## Python (ens-normalize-python by NameHash)

### Main Functions
```python
# Main normalization - raises DisallowedSequence
ens_normalize(text: str) → str

# Beautify for display - raises DisallowedSequence  
ens_beautify(text: str) → str

# Attempt to fix by removing disallowed chars
ens_cure(text: str) → str

# Tokenize - returns token list
ens_tokenize(input: str) → List[Token]

# Get normalization details
ens_normalizations(input: str) → List[NormalizableSequence]
```

### Error Handling
- Custom exception hierarchy (DisallowedSequence, CurableSequence)
- Detailed error metadata (type, index, sequence)
- Supports both raising and non-raising modes

### Key Characteristics
- Simple string in/string out API
- Stateless functions
- Additional "cure" function not in JS
- More detailed error information

## Our Zig Implementation

### Current API
```zig
// Stateful normalizer object
pub const EnsNameNormalizer = struct {
    // Constructor
    init(allocator, specs) → EnsNameNormalizer
    default(allocator) → EnsNameNormalizer
    
    // Methods
    tokenize(input: []const u8) → TokenizedName
    process(input: []const u8) → ProcessedName
    normalize(input: []const u8) → []u8
    beautify_fn(input: []const u8) → []u8
}

// Convenience functions (stateless)
pub fn tokenize(allocator, input: []const u8) → TokenizedName
pub fn process(allocator, input: []const u8) → ProcessedName  
pub fn normalize(allocator, input: []const u8) → []u8
pub fn beautify(allocator, input: []const u8) → []u8
```

### Error Handling
- Returns Zig errors (e.g., error.DisallowedSequence)
- Less detailed error information compared to references

### Key Differences from References

1. **Stateful vs Stateless**
   - References: All stateless functions
   - Zig: Both stateful object and stateless functions

2. **Memory Management**
   - References: Automatic (GC languages)
   - Zig: Manual with allocator parameter

3. **Missing Functions**
   - No `split` function (like JS)
   - No `cure` function (like Python)
   - No `normalize_fragment` function (like JS)

4. **API Complexity**
   - References: Simple string→string
   - Zig: More complex with ProcessedName intermediate type

5. **Function Naming**
   - References: `ens_beautify`
   - Zig: `beautify_fn` (inconsistent naming)

## Recommendations

1. **Simplify API**: Focus on stateless functions that match references
2. **Add Missing Functions**: Implement `split` and potentially `normalize_fragment`
3. **Improve Error Handling**: Add more detailed error information
4. **Consistent Naming**: Use `ens_` prefix like references or drop prefixes entirely
5. **Hide Complexity**: Keep ProcessedName internal, expose simple string APIs