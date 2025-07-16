# ENS Normalize API Analysis

## Summary of Reference Implementations

Based on my analysis of the JavaScript and Python implementations, here are the key findings:

### Common API Pattern Across References

1. **Simple String-Based API**
   - All reference implementations use simple string in/string out functions
   - No stateful normalizer objects - just pure functions
   - Functions are exported at the module level

2. **Core Functions Present in All Implementations**
   - `normalize(string) → string` - Main normalization, throws on invalid
   - `beautify(string) → string` - Display-ready output, throws on invalid
   - `tokenize(string) → Token[]` - Low-level tokenization, never throws

3. **Error Handling**
   - All throw/raise descriptive errors for invalid names
   - Errors contain enough information to understand what went wrong
   - JavaScript shows non-printable chars as {HEX}
   - Python has detailed error objects with type, index, and sequence info

4. **Memory Management**
   - JavaScript/Python: Automatic (garbage collected)
   - Go/Rust/C#: Would need to handle allocation appropriately
   - But the API surface remains simple - users don't see allocation details

### Additional Functions by Implementation

**JavaScript (adraffy/ens-normalize.js)**
- `ens_normalize_fragment(frag, decompose?)` - Normalizes fragments that would fail full validation
- `ens_split(name, preserve_emoji?)` - Splits name into labels with metadata

**Python (namehash/ens-normalize-python)**
- `ens_cure(text)` - Attempts to fix by removing disallowed characters
- `ens_normalizations(input)` - Returns detailed normalization steps

### Key Differences in Our Zig Implementation

1. **Overly Complex API**
   - We expose both a stateful `EnsNameNormalizer` object AND stateless functions
   - We expose intermediate types like `ProcessedName` and `TokenizedName`
   - References hide all this complexity

2. **Inconsistent Function Naming**
   - We use `beautify_fn` instead of `beautify` (to avoid keyword conflict?)
   - No consistent prefix pattern (some have `ens_`, some don't)

3. **Missing Functions**
   - No `split` function for breaking names into labels
   - No `normalize_fragment` for partial normalization
   - No equivalent to Python's `cure` function

4. **Allocation Complexity Exposed**
   - Every function requires an allocator parameter
   - Users must manage memory explicitly
   - References hide this completely

5. **Less Detailed Error Information**
   - We have error types but less metadata
   - No position/index information in errors
   - No hex representation of invalid characters

## Recommendations for API Improvements

### 1. Simplify to Match References

```zig
// Primary API - simple string functions
pub fn normalize(allocator: Allocator, input: []const u8) ![]u8
pub fn beautify(allocator: Allocator, input: []const u8) ![]u8
pub fn tokenize(allocator: Allocator, input: []const u8) ![]Token

// Additional functions from references
pub fn normalizeFragment(allocator: Allocator, input: []const u8) ![]u8
pub fn split(allocator: Allocator, input: []const u8) ![]Label
```

### 2. Hide Internal Complexity

- Remove `EnsNameNormalizer` from public API
- Remove `ProcessedName` from public API
- Keep these as internal implementation details

### 3. Improve Error Handling

```zig
pub const NormalizationError = struct {
    type: ErrorType,
    message: []const u8,
    position: ?usize,
    sequence: ?[]const u8,
    
    pub fn format(self: @This(), allocator: Allocator) ![]u8
};
```

### 4. Consider a Higher-Level Wrapper

For users who don't want to manage allocators:

```zig
pub const SimpleNormalizer = struct {
    allocator: Allocator,
    
    pub fn init(allocator: Allocator) @This()
    pub fn normalize(self: @This(), input: []const u8) ![]u8
    pub fn beautify(self: @This(), input: []const u8) ![]u8
};
```

### 5. Match Reference Behavior Exactly

- Tokenize should NEVER fail (currently it can)
- Errors should format non-printable chars as {HEX}
- Fragment normalization should allow partial/invalid sequences

## Implementation Priority

1. **First**: Simplify existing API to match references
2. **Second**: Add missing `split` and `normalizeFragment` functions
3. **Third**: Improve error handling with more metadata
4. **Fourth**: Ensure 100% compatibility with reference test cases

The goal is to make our API as simple and predictable as the JavaScript and Python references while properly handling Zig's manual memory management requirements.