# Complete spec.json Data Loading Implementation

## Overview

The current implementation uses basic fallback mappings instead of loading the complete spec.json data. This document outlines the implementation plan for loading and using the full ENS normalization specification data.

## Current Limitations

1. **Partial Mapping Data**: Only loading essential mappings manually
2. **Missing Groups**: Not loading script groups (Latin, Greek, Arabic, etc.)
3. **No Emoji Data**: Emoji sequences not loaded
4. **No Fenced Characters**: Missing fenced character definitions
5. **No Whole Confusables**: Missing whole-script confusable data
6. **No NFC Check**: Missing NFC normalization check data

## spec.json Structure

Based on analysis of the actual spec.json file:

```json
{
  "unicode": "15.0.0",
  "cldr": "43.0.0",
  "created": "2023-09-13T04:57:00.677Z",
  "mapped": {
    // Format: "index": [from_cp, [to_cp1, to_cp2, ...]]
    "0": [39, [8217]],         // ' → '
    "1": [65, [97]],           // A → a
    "2": [66, [98]],           // B → b
    // ... continues for all mapped characters
  },
  "ignored": [173, 8204, 8205, 65279, ...],  // Ignored code points
  "cm": [768, 769, 770, ...],                // Combining marks
  "nsm": [768, 769, 770, ...],               // Non-spacing marks
  "nsm_max": 4,                              // Max consecutive NSMs
  "escape": [8206, 8207, ...],               // Should be escaped in output
  "nfc_check": [...],                        // Characters that need NFC check
  "fenced": {
    // Format: "cp": "script_name"
    "39": "ASCII",
    "1523": "Hebrew",
    // ...
  },
  "groups": [
    {
      "name": "Latin",
      "primary": [36, 45, 48, 49, ...],    // Primary valid code points
      "secondary": [960],                   // Secondary valid code points
      "cm": []                              // Allowed combining marks
    },
    {
      "name": "Greek",
      "primary": [...],
      "secondary": [...],
      "cm": [...]
    },
    // ... more script groups
  ],
  "emoji": [...],                          // Emoji sequences
  "whole_map": [...],                      // Whole script confusables
  "wholes": [...]                          // Whole confusable data
}
```

## Implementation Plan

### 1. Update Data Structures

```zig
pub const SpecData = struct {
    unicode_version: []const u8,
    cldr_version: []const u8,
    mapped: std.AutoHashMap(CodePoint, []const CodePoint),
    ignored: std.AutoHashMap(CodePoint, void),
    cm: std.AutoHashMap(CodePoint, void),
    nsm: std.AutoHashMap(CodePoint, void),
    nsm_max: u32,
    escape: std.AutoHashMap(CodePoint, void),
    nfc_check: std.AutoHashMap(CodePoint, void),
    fenced: std.AutoHashMap(CodePoint, []const u8),
    groups: []ScriptGroup,
    emoji: []EmojiSequence,
    whole_map: []WholeConfusable,
    allocator: std.mem.Allocator,
};

pub const ScriptGroup = struct {
    name: []const u8,
    primary: []CodePoint,
    secondary: []CodePoint,
    cm: []CodePoint,
};

pub const EmojiSequence = struct {
    sequence: []CodePoint,
    type: EmojiType,
};

pub const WholeConfusable = struct {
    // TBD based on spec analysis
};
```

### 2. JSON Parsing Strategy

Since the spec.json is large (11MB), we need an efficient parsing strategy:

1. **Streaming Parse**: Use a streaming JSON parser if available
2. **Selective Loading**: Only load data we currently need
3. **Lazy Loading**: Load sections on demand
4. **Memory Optimization**: Use arena allocators for temporary data

### 3. Update Static Data Loader

```zig
pub fn loadCompleteSpec(allocator: std.mem.Allocator) !SpecData {
    const json_data = @embedFile("static_data/spec.json");
    
    // Parse JSON in chunks to avoid memory issues
    var parser = std.json.Parser.init(allocator, false);
    defer parser.deinit();
    
    var spec = SpecData{
        .allocator = allocator,
        // ... initialize fields
    };
    
    // Load mapped characters
    try loadMappedFromSpec(&spec, json_root);
    
    // Load ignored characters
    try loadIgnoredFromSpec(&spec, json_root);
    
    // Load script groups
    try loadGroupsFromSpec(&spec, json_root);
    
    // Load other sections as needed
    
    return spec;
}
```

### 4. Integration Points

1. **Character Mappings**: Update to use complete mapped data
2. **Validation**: Use groups for script detection
3. **Confusables**: Implement whole-script confusable checking
4. **Emoji**: Add emoji sequence detection
5. **Fenced Characters**: Implement fenced character rules

## Reference Implementations

### JavaScript (ens-normalize.js)
- Uses compressed binary format for efficiency
- Decodes data on initialization
- Implements custom decoder for compact representation

### Go (go-ens-normalize)
- Uses embedded binary file (spec.bin)
- Custom binary decoder
- Efficient memory usage with specialized data structures

### Python (ens-normalize-python)
- Uses pickled data for fast loading
- Falls back to JSON if pickle unavailable
- Caches parsed data

### Rust (ens-normalize-rs)
- Uses JSON with serde
- Loads all data at once
- Uses HashMap for lookups

## Testing Strategy

1. **Data Integrity Tests**: Verify loaded data matches spec.json
2. **Performance Tests**: Measure loading time and memory usage
3. **Compatibility Tests**: Ensure results match reference implementations
4. **Edge Case Tests**: Test with large inputs, unusual characters

## Performance Considerations

1. **Compile-Time Embedding**: Use `@embedFile` for zero-runtime loading
2. **Lazy Initialization**: Only parse what's needed
3. **Memory Pooling**: Use arena allocators for temporary data
4. **Lookup Optimization**: Use perfect hash functions if possible

## Implementation Steps

1. ✅ Create basic CharacterMappings structure
2. ✅ Implement fallback mappings for testing
3. ⬜ Parse complete mapped section from spec.json
4. ⬜ Parse and store script groups
5. ⬜ Implement group-based validation
6. ⬜ Add emoji sequence support
7. ⬜ Add fenced character checking
8. ⬜ Add whole-script confusable detection
9. ⬜ Optimize memory usage
10. ⬜ Add comprehensive tests

## Next Actions

1. Start with parsing the complete "mapped" section
2. Add support for "ignored" characters
3. Implement basic group loading
4. Test against reference implementations
5. Iterate on performance and correctness