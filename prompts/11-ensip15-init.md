# Task 11: Implement ENSIP15 Initialization

## Goal

Port the ENSIP15.New() constructor from Go to Zig as an `init()` method. This function loads `spec.bin` and builds all normalization data structures required for ENS name processing.

The initialization:
- Embeds and decodes the binary spec file
- Loads escape, ignored, combining marks, and other rune sets
- Decodes mapped characters and fenced codepoints
- Loads groups, emojis, and confusables
- Builds an emoji tree for sequence matching
- Constructs possiblyValid and uniqueNonConfusables sets
- Creates direct references to commonly-used groups (LATIN, GREEK, ASCII, EMOJI)

## Go Reference Code

### Helper Functions (Lines 38-70)

```go
func decodeNamedCodepoints(d *util.Decoder) map[rune]string {
	ret := make(map[rune]string)
	for _, cp := range d.ReadSortedAscending(d.ReadUnsigned()) {
		ret[rune(cp)] = d.ReadString()
	}
	return ret
}

func decodeMapped(d *util.Decoder) map[rune][]rune {
	ret := make(map[rune][]rune)
	for {
		w := d.ReadUnsigned()
		if w == 0 {
			break
		}
		keys := d.ReadSortedUnique()
		n := len(keys)
		m := make([][]rune, n)
		for i := 0; i < n; i++ {
			m[i] = make([]rune, w)
		}
		for j := 0; j < w; j++ {
			v := d.ReadUnsortedDeltas(n)
			for i := 0; i < n; i++ {
				m[i][j] = rune(v[i])
			}
		}
		for i := 0; i < n; i++ {
			ret[rune(keys[i])] = m[i]
		}
	}
	return ret
}
```

### New() Constructor (Lines 72-140)

```go
func New() *ENSIP15 {
	d := util.NewDecoder(compressed)
	l := ENSIP15{}
	l.nf = nf.New()
	l.shouldEscape = util.NewRuneSetFromInts(d.ReadUnique())
	l.ignored = util.NewRuneSetFromInts(d.ReadUnique())
	l.combiningMarks = util.NewRuneSetFromInts(d.ReadUnique())
	l.maxNonSpacingMarks = d.ReadUnsigned()
	l.nonSpacingMarks = util.NewRuneSetFromInts(d.ReadUnique())
	l.nfcCheck = util.NewRuneSetFromInts(d.ReadUnique())
	l.fenced = decodeNamedCodepoints(d)
	l.mapped = decodeMapped(d)
	l.groups = decodeGroups(d)
	l.emojis = decodeEmojis(d, nil)
	l.wholes, l.confusables = decodeWholes(d, l.groups)
	d.AssertEOF()

	sort.Slice(l.emojis, func(i, j int) bool {
		return compareRunes(l.emojis[i].normalized, l.emojis[j].normalized) < 0
	})

	l.emojiRoot = makeEmojiTree(l.emojis)

	union := make(map[rune]bool)
	multi := make(map[rune]bool)
	for _, g := range l.groups {
		for _, cp := range append(g.primary.ToArray(), g.secondary.ToArray()...) {
			if union[cp] {
				multi[cp] = true
			} else {
				union[cp] = true
			}
		}
	}

	possiblyValid := make(map[rune]bool)
	for cp := range union {
		possiblyValid[cp] = true
		for _, cp := range l.nf.NFD([]rune{cp}) {
			possiblyValid[cp] = true
		}
	}
	l.possiblyValid = util.NewRuneSetFromKeys(possiblyValid)

	for cp := range multi {
		delete(union, cp)
	}
	for cp := range l.confusables {
		delete(union, cp)
	}
	l.uniqueNonConfusables = util.NewRuneSetFromKeys(union)

	// direct group references
	l._LATIN = l.FindGroup("Latin")
	l._GREEK = l.FindGroup("Greek")
	l._ASCII = &Group{
		index:         -1,
		restricted:    false,
		name:          "ASCII",
		cmWhitelisted: false,
		primary:       l.possiblyValid.Filter(func(cp rune) bool { return cp < 0x80 }),
	}
	l._EMOJI = &Group{
		index:         -1,
		restricted:    false,
		cmWhitelisted: false,
	}
	return &l
}
```

## Implementation Guidance

### Understanding spec.bin Structure

The binary spec file contains the following data in sequence:

1. **shouldEscape**: RuneSet of codepoints that must be escaped
2. **ignored**: RuneSet of codepoints to ignore during normalization
3. **combiningMarks**: RuneSet of all combining marks
4. **maxNonSpacingMarks**: unsigned integer limit
5. **nonSpacingMarks**: RuneSet of non-spacing marks
6. **nfcCheck**: RuneSet requiring NFC validation
7. **fenced**: Map of rune → string (named codepoints with context)
8. **mapped**: Map of rune → []rune (complex mapping structure)
9. **groups**: Script groups (e.g., Latin, Greek, Han)
10. **emojis**: Emoji sequences and patterns
11. **wholes**: Whole-script confusables data

Each section is decoded sequentially using the Decoder.

### @embedFile Usage

```zig
const spec_data = @embedFile("spec.bin");
```

This embeds the binary file at compile time. Pass it to the Decoder:

```zig
var decoder = Decoder.init(spec_data);
```

### Decode Helper Functions

#### decodeNamedCodepoints()

Reads a map of codepoint → name. Used for fenced codepoints that have special context.

**Algorithm:**
1. Read count (unsigned)
2. Read sorted ascending codepoint list
3. For each codepoint, read its string name
4. Return HashMap

**Stub Implementation:**
```zig
fn decodeNamedCodepoints(decoder: *Decoder, allocator: Allocator) !std.AutoHashMap(u21, []const u8) {
    @panic("TODO: Task 11 - decodeNamedCodepoints");
}
```

#### decodeMapped()

Reads complex mapped array structure. Each codepoint maps to a sequence of runes.

**Algorithm:**
1. Loop until width == 0:
   - Read width w (unsigned)
   - If w == 0, break
   - Read sorted unique keys
   - Build n×w matrix (n keys, w runes each)
   - For each position j in width:
     - Read unsorted deltas for all n keys
   - Store each key → rune sequence in map
2. Return HashMap

**Stub Implementation:**
```zig
fn decodeMapped(decoder: *Decoder, allocator: Allocator) !std.AutoHashMap(u21, []const u21) {
    @panic("TODO: Task 11 - decodeMapped");
}
```

### Emoji Tree Construction

After loading emojis, they must be sorted lexicographically by normalized form:

```zig
// Sort emojis by normalized sequence
std.sort.block(Emoji, emojis.items, {}, emojiLessThan);

fn emojiLessThan(context: void, a: Emoji, b: Emoji) bool {
    _ = context;
    return compareRunes(a.normalized, b.normalized) < 0;
}
```

Then build the emoji tree:

```zig
emoji_root = makeEmojiTree(emojis.items);  // Stubbed in this task
```

### possiblyValid Set Construction

This set contains all codepoints that could appear in valid names:

**Algorithm:**
1. Create `union` map: collect all primary and secondary codepoints from all groups
2. Track `multi` map: codepoints appearing in multiple groups
3. Create `possiblyValid` map:
   - Add all codepoints from union
   - For each codepoint, add all its NFD decomposition codepoints
4. Convert to RuneSet

**Stub Implementation:**
```zig
var union = std.AutoHashMap(u21, void).init(allocator);
var multi = std.AutoHashMap(u21, void).init(allocator);

for (groups.items) |group| {
    // Iterate primary codepoints
    var it = group.primary.iterator();
    while (it.next()) |cp| {
        if (union.contains(cp)) {
            try multi.put(cp, {});
        } else {
            try union.put(cp, {});
        }
    }
    // Same for secondary
}

var possibly_valid = std.AutoHashMap(u21, void).init(allocator);
var union_it = union.keyIterator();
while (union_it.next()) |cp_ptr| {
    const cp = cp_ptr.*;
    try possibly_valid.put(cp, {});

    // Add NFD decomposition
    const nfd_result = nf.nfd(&[_]u21{cp});
    for (nfd_result) |nfd_cp| {
        try possibly_valid.put(nfd_cp, {});
    }
}
```

### uniqueNonConfusables Set Construction

This set contains codepoints that uniquely identify a script (not confusable, not in multiple groups):

**Algorithm:**
1. Start with `union` from above
2. Remove all codepoints in `multi` (appear in multiple groups)
3. Remove all codepoints in `confusables` map
4. Convert to RuneSet

```zig
var multi_it = multi.keyIterator();
while (multi_it.next()) |cp_ptr| {
    _ = union.remove(cp_ptr.*);
}

var conf_it = confusables.keyIterator();
while (conf_it.next()) |cp_ptr| {
    _ = union.remove(cp_ptr.*);
}

unique_non_confusables = RuneSet.fromKeys(union);
```

### Direct Group References

Four groups are cached for fast access:

1. **_LATIN**: Found via `findGroup("Latin")`
2. **_GREEK**: Found via `findGroup("Greek")`
3. **_ASCII**: Synthetic group, primary = possiblyValid filtered to < 0x80
4. **_EMOJI**: Synthetic group, minimal fields

```zig
_LATIN = findGroup(self, "Latin"),
_GREEK = findGroup(self, "Greek"),
_ASCII = Group{
    .index = -1,
    .restricted = false,
    .name = "ASCII",
    .cm_whitelisted = false,
    .primary = possiblyValid.filter(isAscii),
    .secondary = RuneSet.init(allocator),
},
_EMOJI = Group{
    .index = -1,
    .restricted = false,
    .name = "EMOJI",
    .cm_whitelisted = false,
    .primary = RuneSet.init(allocator),
    .secondary = RuneSet.init(allocator),
},
```

### Helper Functions to Define (Stubs)

These functions will be implemented in later tasks. For now, stub them:

```zig
fn decodeGroups(decoder: *Decoder, allocator: Allocator) ![]Group {
    @panic("TODO: Task XX - decodeGroups");
}

fn decodeEmojis(decoder: *Decoder, allocator: Allocator) ![]Emoji {
    @panic("TODO: Task XX - decodeEmojis");
}

fn decodeWholes(decoder: *Decoder, groups: []Group, allocator: Allocator) !struct {
    wholes: std.AutoHashMap(u21, WholeConfusable),
    confusables: std.AutoHashMap(u21, void),
} {
    @panic("TODO: Task XX - decodeWholes");
}

fn makeEmojiTree(emojis: []Emoji, allocator: Allocator) !*EmojiNode {
    @panic("TODO: Task XX - makeEmojiTree");
}

fn findGroup(self: *Ensip15, name: []const u8) ?*Group {
    @panic("TODO: Task XX - findGroup");
}
```

### init() Method Signature

```zig
pub fn init(allocator: Allocator) !Ensip15 {
    // Implementation here
}
```

## File Location

Create: `/Users/williamcory/z-ens-normalize/src/ensip15/ensip15.zig`

## Dependencies

This task requires:

- **Task 01**: Decoder implementation
- **Task 02**: RuneSet implementation
- **Task 03**: NF (normalization forms) implementation
- **Task 04**: spec.bin file in correct location
- **Task 06**: ENSIP15 types (Ensip15, Group, Emoji, etc.)
- **Task 07**: Error types

## Implementation Steps

1. **Import dependencies:**
   ```zig
   const std = @import("std");
   const Decoder = @import("../decoder.zig").Decoder;
   const RuneSet = @import("../runeset.zig").RuneSet;
   const NF = @import("../nf.zig").NF;
   const Ensip15 = @import("types.zig").Ensip15;
   const Group = @import("types.zig").Group;
   const Emoji = @import("types.zig").Emoji;
   const Allocator = std.mem.Allocator;
   ```

2. **Embed spec.bin:**
   ```zig
   const spec_data = @embedFile("spec.bin");
   ```

3. **Define helper functions (stubbed):**
   - `decodeNamedCodepoints()`
   - `decodeMapped()`
   - `decodeGroups()` (stub)
   - `decodeEmojis()` (stub)
   - `decodeWholes()` (stub)
   - `makeEmojiTree()` (stub)
   - `findGroup()` (stub)
   - `emojiLessThan()` (stub)
   - `compareRunes()` (stub)
   - `isAscii()` (helper for filter)

4. **Implement init() method:**
   ```zig
   pub fn init(allocator: Allocator) !Ensip15 {
       var decoder = Decoder.init(spec_data);

       var result = Ensip15{
           .allocator = allocator,
           .nf = try NF.init(),
           .should_escape = undefined,
           .ignored = undefined,
           .combining_marks = undefined,
           .max_non_spacing_marks = undefined,
           .non_spacing_marks = undefined,
           .nfc_check = undefined,
           .fenced = undefined,
           .mapped = undefined,
           .groups = undefined,
           .emojis = undefined,
           .wholes = undefined,
           .confusables = undefined,
           .emoji_root = undefined,
           .possibly_valid = undefined,
           .unique_non_confusables = undefined,
           ._LATIN = undefined,
           ._GREEK = undefined,
           ._ASCII = undefined,
           ._EMOJI = undefined,
       };

       // Decode binary spec
       result.should_escape = try RuneSet.fromInts(decoder.readUnique(), allocator);
       result.ignored = try RuneSet.fromInts(decoder.readUnique(), allocator);
       result.combining_marks = try RuneSet.fromInts(decoder.readUnique(), allocator);
       result.max_non_spacing_marks = decoder.readUnsigned();
       result.non_spacing_marks = try RuneSet.fromInts(decoder.readUnique(), allocator);
       result.nfc_check = try RuneSet.fromInts(decoder.readUnique(), allocator);
       result.fenced = try decodeNamedCodepoints(&decoder, allocator);
       result.mapped = try decodeMapped(&decoder, allocator);
       result.groups = try decodeGroups(&decoder, allocator);
       result.emojis = try decodeEmojis(&decoder, allocator);

       const wholes_result = try decodeWholes(&decoder, result.groups, allocator);
       result.wholes = wholes_result.wholes;
       result.confusables = wholes_result.confusables;

       try decoder.assertEOF();

       // Sort emojis
       std.sort.block(Emoji, result.emojis, {}, emojiLessThan);

       // Build emoji tree
       result.emoji_root = try makeEmojiTree(result.emojis, allocator);

       // Build union and multi sets
       var union = std.AutoHashMap(u21, void).init(allocator);
       var multi = std.AutoHashMap(u21, void).init(allocator);

       for (result.groups) |group| {
           // Process primary
           var primary_it = group.primary.iterator();
           while (primary_it.next()) |cp| {
               if (union.contains(cp)) {
                   try multi.put(cp, {});
               } else {
                   try union.put(cp, {});
               }
           }
           // Process secondary
           var secondary_it = group.secondary.iterator();
           while (secondary_it.next()) |cp| {
               if (union.contains(cp)) {
                   try multi.put(cp, {});
               } else {
                   try union.put(cp, {});
               }
           }
       }

       // Build possiblyValid
       var possibly_valid = std.AutoHashMap(u21, void).init(allocator);
       var union_it = union.keyIterator();
       while (union_it.next()) |cp_ptr| {
           const cp = cp_ptr.*;
           try possibly_valid.put(cp, {});

           const nfd_result = result.nf.nfd(&[_]u21{cp});
           for (nfd_result) |nfd_cp| {
               try possibly_valid.put(nfd_cp, {});
           }
       }
       result.possibly_valid = try RuneSet.fromKeys(possibly_valid, allocator);

       // Build uniqueNonConfusables
       var multi_it = multi.keyIterator();
       while (multi_it.next()) |cp_ptr| {
           _ = union.remove(cp_ptr.*);
       }
       var conf_it = result.confusables.keyIterator();
       while (conf_it.next()) |cp_ptr| {
           _ = union.remove(cp_ptr.*);
       }
       result.unique_non_confusables = try RuneSet.fromKeys(union, allocator);

       // Direct group references
       result._LATIN = findGroup(&result, "Latin");
       result._GREEK = findGroup(&result, "Greek");
       result._ASCII = Group{
           .index = -1,
           .restricted = false,
           .name = "ASCII",
           .cm_whitelisted = false,
           .primary = try result.possibly_valid.filter(isAscii, allocator),
           .secondary = try RuneSet.init(allocator),
       };
       result._EMOJI = Group{
           .index = -1,
           .restricted = false,
           .name = "EMOJI",
           .cm_whitelisted = false,
           .primary = try RuneSet.init(allocator),
           .secondary = try RuneSet.init(allocator),
       };

       return result;
   }
   ```

5. **Add to build.zig:**
   Ensure `src/ensip15/ensip15.zig` is compiled as part of the library.

## Success Criteria

- [ ] File `src/ensip15/ensip15.zig` created
- [ ] `decodeNamedCodepoints()` helper defined (stubbed with @panic)
- [ ] `decodeMapped()` helper defined (stubbed with @panic)
- [ ] `decodeGroups()` stubbed
- [ ] `decodeEmojis()` stubbed
- [ ] `decodeWholes()` stubbed
- [ ] `makeEmojiTree()` stubbed
- [ ] `findGroup()` stubbed
- [ ] `emojiLessThan()` stubbed
- [ ] `compareRunes()` stubbed
- [ ] `init()` method signature: `pub fn init(allocator: Allocator) !Ensip15`
- [ ] `@embedFile("spec.bin")` declared at module level
- [ ] Decoder initialization present
- [ ] All decode calls present in correct order
- [ ] Emoji sorting call present
- [ ] Emoji tree construction call present
- [ ] `possiblyValid` set construction present
- [ ] `uniqueNonConfusables` set construction present
- [ ] Group references (`_LATIN`, `_GREEK`, `_ASCII`, `_EMOJI`) initialized
- [ ] File compiles without errors
- [ ] `zig build` succeeds

## Validation Commands

```bash
# Compile the project
zig build

# Expected output:
# Build should succeed (though init will panic if called due to stubs)
```

## Common Pitfalls

1. **Don't implement decoder methods yet**: Just call the methods. The Decoder implementation is Task 01.

2. **Helper functions can panic with TODO**: Use `@panic("TODO: Task XX - <function_name>")` for unimplemented helpers. This allows the file to compile while marking what needs implementation.

3. **Emoji tree and group decoding are separate tasks**: These are complex and will be implemented later. Just stub the calls.

4. **Use std.AutoHashMap for runtime maps**: The Go code uses `make(map[...])` which translates to `std.AutoHashMap` in Zig. These must be initialized with an allocator.

5. **ASCII and EMOJI are synthetic groups**: They're created in `init()`, not decoded from spec.bin. ASCII filters possiblyValid to codepoints < 0x80.

6. **Memory management**: All allocations (HashMaps, RuneSets, slices) must use the provided allocator. Consider implementing a `deinit()` method to free resources.

7. **Decoder is stateful**: Each read advances the position. The order of reads must exactly match the order data was written to spec.bin.

8. **assertEOF is important**: After decoding, verify the entire file was consumed. This catches version mismatches or corrupted files.

9. **Group references can be null**: `findGroup()` may return null if the group doesn't exist. Handle this appropriately (or panic during init if critical groups are missing).

10. **Filter function signature**: When implementing `possiblyValid.filter(isAscii)`, ensure `isAscii` has the correct signature for RuneSet's filter method.

## Notes

- The init() function performs all setup at once. There's no lazy loading.
- Error handling: Use `!Ensip15` return type and propagate errors with `try`.
- Consider using `defer` for cleanup if init fails partway through.
- The Go code returns a pointer `*ENSIP15`, but in Zig we can return the value directly and let the caller decide on storage.

## References

- Go source: `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/ensip15.go` lines 38-140
- ENSIP-15 spec: https://docs.ens.domains/ensip/15
