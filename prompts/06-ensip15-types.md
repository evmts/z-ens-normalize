# Task 06: Port ENSIP15 Core Data Structures

## Goal

Port all main data structures for ENSIP15 normalization to `src/ensip15/types.zig`. These structures form the core of the ENSIP15 implementation and hold references to embedded specification data.

## Context

The ENSIP15 specification defines how ENS names should be normalized. The main types include:
- **ENSIP15**: The main context holding all normalization data (no allocator stored)
- **Group**: Represents script groups (Latin, Greek, Han, etc.)
- **EmojiSequence**: Represents valid emoji sequences with normalized and beautified forms
- **EmojiNode**: Tree structure for efficient emoji parsing
- **Whole**: Represents confusable character groups
- **OutputToken**: Intermediate representation during normalization

All structs hold references to embedded data - no allocations occur in struct initialization.

## Go Reference Code

### ENSIP15 Main Struct

From `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/ensip15.go` lines 15-36:

```go
type ENSIP15 struct {
	nf                   *nf.NF
	shouldEscape         util.RuneSet
	ignored              util.RuneSet
	combiningMarks       util.RuneSet
	nonSpacingMarks      util.RuneSet
	maxNonSpacingMarks   int
	nfcCheck             util.RuneSet
	fenced               map[rune]string
	mapped               map[rune][]rune
	groups               []*Group
	emojis               []EmojiSequence
	emojiRoot            *EmojiNode
	possiblyValid        util.RuneSet
	wholes               []Whole
	confusables          map[rune]Whole
	uniqueNonConfusables util.RuneSet
	_LATIN               *Group
	_GREEK               *Group
	_ASCII               *Group
	_EMOJI               *Group
}
```

### Group Struct

From `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/groups.go` lines 10-17:

```go
type Group struct {
	index         int
	name          string
	restricted    bool
	cmWhitelisted bool
	primary       util.RuneSet
	secondary     util.RuneSet
}
```

Key methods:
```go
func (g *Group) Name() string {
	return g.name
}

func (g *Group) String() string {
	if g.restricted {
		return fmt.Sprintf("Restricted[%s]", g.name)
	} else {
		return g.name
	}
}

func (g *Group) IsRestricted() bool {
	return g.restricted
}

func (g *Group) Contains(cp rune) bool {
	return g.primary.Contains(cp) || g.secondary.Contains(cp)
}
```

### Emoji Types

From `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/emojis.go` lines 12-36:

```go
type EmojiSequence struct {
	normalized []rune
	beautified []rune
}

func (seq EmojiSequence) Normalized() string {
	return string(seq.normalized)
}

func (seq EmojiSequence) Beautified() string {
	return string(seq.beautified)
}

func (seq EmojiSequence) String() string {
	return seq.Beautified()
}

func (seq EmojiSequence) IsMangled() bool {
	return len(seq.normalized) < len(seq.beautified)
}

func (seq EmojiSequence) HasZWJ() bool {
	for _, x := range seq.beautified {
		if x == ZWJ {
			return true
		}
	}
	return false
}
```

From `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/emojis.go` lines 63-78:

```go
type EmojiNode struct {
	emoji    *EmojiSequence
	children map[rune]*EmojiNode
}

func (node *EmojiNode) Child(cp rune) *EmojiNode {
	if node.children == nil {
		node.children = make(map[rune]*EmojiNode)
	}
	child, ok := node.children[cp]
	if !ok {
		child = &EmojiNode{}
		node.children[cp] = child
	}
	return child
}
```

### Whole Struct

From `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/wholes.go` lines 11-15:

```go
type Whole struct {
	valid       util.RuneSet
	confused    util.RuneSet
	complements map[rune][]int
}
```

### OutputToken Struct

From `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/output.go` lines 7-18:

```go
type OutputToken struct {
	Codepoints []rune
	Emoji      *EmojiSequence
}

func (ot OutputToken) String() string {
	if ot.Emoji != nil {
		return fmt.Sprintf("Emoji[%s]", ToHexSequence(ot.Emoji.normalized))
	} else {
		return fmt.Sprintf("Text[%s]", ToHexSequence(ot.Codepoints))
	}
}
```

## Implementation Guidance

### Type Mapping Patterns

**Go to Zig type mappings:**
- `util.RuneSet` → `RuneSet` (from `src/util/runeset.zig`)
- `*nf.NF` → `*NF` (from `src/nf/nf.zig`)
- `map[rune]string` → `std.AutoHashMap(u21, []const u8)`
- `map[rune][]rune` → `std.AutoHashMap(u21, []const u21)`
- `map[rune]Whole` → `std.AutoHashMap(u21, Whole)`
- `[]*Group` → `[]*const Group` or `[]const *const Group`
- `[]EmojiSequence` → `[]const EmojiSequence`
- `[]Whole` → `[]const Whole`
- `[]rune` → `[]const u21`
- `string` → `[]const u8`
- `int` → `usize` or `i32` (context-dependent)
- `bool` → `bool`

### Key Design Principles

1. **No Allocator in Structs**: The ENSIP15 struct does not store an allocator - it only holds references to data
2. **Const Correctness**: Use `const` pointers and slices where data won't be modified
3. **Embedded Data References**: All RuneSets, maps, and slices reference embedded specification data
4. **Stub Methods**: All helper methods should be stubbed with `@panic("TODO: implement")`
5. **Optional Pointers**: Use `?*EmojiSequence` for nullable emoji references

### Struct Organization

Create the file with this structure:

```zig
const std = @import("std");
const RuneSet = @import("../util/runeset.zig").RuneSet;
const NF = @import("../nf/nf.zig").NF;

/// Main ENSIP15 normalization context
pub const ENSIP15 = struct {
    // Core NF reference
    nf: *const NF,

    // RuneSets for character classification
    should_escape: RuneSet,
    ignored: RuneSet,
    combining_marks: RuneSet,
    non_spacing_marks: RuneSet,
    max_non_spacing_marks: usize,
    nfc_check: RuneSet,
    possibly_valid: RuneSet,
    unique_non_confusables: RuneSet,

    // Maps for transformations
    fenced: std.AutoHashMap(u21, []const u8),
    mapped: std.AutoHashMap(u21, []const u21),
    confusables: std.AutoHashMap(u21, Whole),

    // Groups and emoji
    groups: []const *const Group,
    emojis: []const EmojiSequence,
    emoji_root: *const EmojiNode,
    wholes: []const Whole,

    // Cached group references
    _LATIN: ?*const Group,
    _GREEK: ?*const Group,
    _ASCII: ?*const Group,
    _EMOJI: ?*const Group,

    // Stub methods
    pub fn normalize(self: *const ENSIP15, name: []const u8) ![]const u8 {
        _ = self;
        _ = name;
        @panic("TODO: implement normalize");
    }

    pub fn beautify(self: *const ENSIP15, name: []const u8) ![]const u8 {
        _ = self;
        _ = name;
        @panic("TODO: implement beautify");
    }

    pub fn normalizeFragment(self: *const ENSIP15, frag: []const u8, decompose: bool) ![]const u8 {
        _ = self;
        _ = frag;
        _ = decompose;
        @panic("TODO: implement normalizeFragment");
    }
};

/// Script group (Latin, Greek, Han, etc.)
pub const Group = struct {
    index: i32,
    name: []const u8,
    restricted: bool,
    cm_whitelisted: bool,
    primary: RuneSet,
    secondary: RuneSet,

    pub fn getName(self: *const Group) []const u8 {
        return self.name;
    }

    pub fn isRestricted(self: *const Group) bool {
        return self.restricted;
    }

    pub fn contains(self: *const Group, cp: u21) bool {
        _ = self;
        _ = cp;
        @panic("TODO: implement contains");
    }
};

/// Emoji sequence with normalized and beautified forms
pub const EmojiSequence = struct {
    normalized: []const u21,
    beautified: []const u21,

    pub fn isMangled(self: *const EmojiSequence) bool {
        return self.normalized.len < self.beautified.len;
    }

    pub fn hasZWJ(self: *const EmojiSequence) bool {
        _ = self;
        @panic("TODO: implement hasZWJ");
    }
};

/// Tree node for emoji parsing
pub const EmojiNode = struct {
    emoji: ?*const EmojiSequence,
    children: ?std.AutoHashMap(u21, *EmojiNode),

    pub fn child(self: *EmojiNode, cp: u21) !*EmojiNode {
        _ = self;
        _ = cp;
        @panic("TODO: implement child");
    }
};

/// Confusable character group
pub const Whole = struct {
    valid: RuneSet,
    confused: RuneSet,
    complements: std.AutoHashMap(u21, []const i32),
};

/// Output token (text or emoji)
pub const OutputToken = struct {
    codepoints: []const u21,
    emoji: ?*const EmojiSequence,
};
```

### Important Notes

1. **HashMap Initialization**: HashMaps will be initialized during the `New()` function (Task 07), not in struct literals
2. **Const Pointers**: Use `*const` for pointers that don't need mutation
3. **Slice Const**: Use `[]const` for slices that reference embedded data
4. **Optional Fields**: Use `?` for nullable pointers (e.g., `?*const Group`)
5. **Method Receivers**: Use `*const Self` for read-only methods
6. **Panic Stubs**: All methods should panic with descriptive TODO messages

## File Location

Create: `src/ensip15/types.zig`

## Dependencies

- `src/util/runeset.zig` - RuneSet type
- `src/nf/nf.zig` - Unicode normalization
- `std.AutoHashMap` - For map types

## Success Criteria

- [ ] File `src/ensip15/types.zig` exists
- [ ] `ENSIP15` struct defined with all fields from Go reference
- [ ] `Group` struct defined with helper methods
- [ ] `EmojiSequence` struct defined
- [ ] `EmojiNode` struct defined
- [ ] `Whole` struct defined
- [ ] `OutputToken` struct defined
- [ ] All struct fields use appropriate Zig types
- [ ] All helper methods stubbed with `@panic("TODO: implement")`
- [ ] File compiles without errors: `zig build`

## Validation Commands

```bash
# Verify file compiles
zig build

# Check for compilation errors in types.zig specifically
zig build-exe src/ensip15/types.zig --mod std::std -femit-bin=/dev/null
```

## Common Pitfalls

1. **Allocator Storage**: Don't store allocator in ENSIP15 struct - it's not in the Go version
2. **HashMap Initialization**: Don't try to initialize HashMaps in struct literals - they need `init()`
3. **Const Slices**: Use `[]const u8` not `[]u8` for embedded string data
4. **Pointer Const**: Use `*const Group` not `*Group` for references to groups
5. **Optional Syntax**: Use `?*const T` not `?*T` for optional const pointers
6. **Method Self**: Use `self: *const Self` not `self: *Self` for read-only methods
7. **Index Types**: Group index should be `i32` (can be -1 for special groups)
8. **Rune Type**: Use `u21` for Unicode codepoints, not `u32`

## Next Steps

After completing this task:
- Task 07 will implement the `New()` constructor that initializes ENSIP15
- Task 08 will implement the decoder for reading embedded spec.bin data
- Task 09 will implement the normalization logic
- Task 10 will implement group determination and validation

## Notes

- This is purely a type definition task - no logic implementation needed
- Focus on getting the types correct and compilable
- All HashMaps will be properly initialized in the constructor (next task)
- The `_LATIN`, `_GREEK`, `_ASCII`, `_EMOJI` fields are cached references set during initialization
