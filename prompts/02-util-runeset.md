# Task 02: Port util/runeset.go to Zig

## Goal

Port the sorted rune set data structure from Go to Zig as `src/util/runeset.zig`. This provides efficient membership testing using binary search over a sorted array of Unicode codepoints.

## Overview

The `RuneSet` is a foundational data structure that wraps a sorted slice of runes (Unicode codepoints) and provides efficient O(log n) membership testing via binary search. It's used throughout the ENS normalization library for character validation and filtering.

## Go Reference Code

```go
package util

import (
	"slices"
	"sort"
)

type RuneSet struct {
	sorted []rune
}

func NewRuneSetFromInts(v []int) RuneSet {
	sorted := make([]rune, len(v))
	for i, x := range v {
		sorted[i] = rune(x)
	}
	sort.Slice(sorted, func(i, j int) bool {
		return sorted[i] < sorted[j]
	})
	return RuneSet{sorted}
}

func NewRuneSetFromKeys[T any](m map[rune]T) RuneSet {
	sorted := make([]rune, 0, len(m))
	for x := range m {
		sorted = append(sorted, x)
	}
	sort.Slice(sorted, func(i, j int) bool {
		return sorted[i] < sorted[j]
	})
	return RuneSet{sorted}
}

func (set RuneSet) Contains(cp rune) bool {
	_, exists := slices.BinarySearch(set.sorted, cp)
	return exists
}

func (set RuneSet) Size() int {
	return len(set.sorted)
}

func (set RuneSet) Filter(fn func(cp rune) bool) RuneSet {
	v := make([]rune, 0, len(set.sorted))
	for _, x := range set.sorted {
		if fn(x) {
			v = append(v, x)
		}
	}
	return RuneSet{v}
}

func (set RuneSet) ToArray() []rune {
	v := make([]rune, len(set.sorted))
	copy(v, set.sorted)
	return v
}
```

## Implementation Guidance

### Key Concepts

1. **Data Structure**: RuneSet wraps a sorted slice of runes (represented as `u21` in Zig, which can hold Unicode codepoints 0x0 to 0x10FFFF)

2. **No Allocations in Init**: The basic constructor just wraps an existing slice - sorting and allocation happen in the factory constructors

3. **Binary Search**: The `Contains()` method uses binary search for O(log n) lookups

4. **Immutability**: The underlying slice should be `[]const u21` to prevent modification

### Zig Specifics

- **Rune Type**: Use `u21` for runes (Unicode codepoints), not `u8` (bytes)
- **Slice Type**: `[]const u21` for the internal sorted slice
- **Method Syntax**: Zig methods are just functions with the struct as first parameter
- **Allocator**: `Filter()` and `ToArray()` will need an allocator for dynamic allocation (stub for now)
- **Function Pointers**: Use `*const fn(u21) bool` for the filter predicate type

### Structure Outline

```zig
const std = @import("std");

pub const RuneSet = struct {
    sorted: []const u21,

    // Constructor - wraps existing sorted slice
    pub fn init(sorted: []const u21) RuneSet {
        @panic("TODO: implement");
    }

    // Factory constructor from integer array
    pub fn fromInts(allocator: std.mem.Allocator, values: []const i32) !RuneSet {
        @panic("TODO: implement");
    }

    // Factory constructor from hash map keys
    pub fn fromKeys(allocator: std.mem.Allocator, map: anytype) !RuneSet {
        @panic("TODO: implement");
    }

    // Check if codepoint exists in set
    pub fn contains(self: RuneSet, cp: u21) bool {
        @panic("TODO: implement");
    }

    // Return number of elements
    pub fn size(self: RuneSet) usize {
        @panic("TODO: implement");
    }

    // Create new RuneSet filtered by predicate
    pub fn filter(self: RuneSet, allocator: std.mem.Allocator, predicate: *const fn(u21) bool) !RuneSet {
        @panic("TODO: implement");
    }

    // Return a copy of the sorted array
    pub fn toArray(self: RuneSet, allocator: std.mem.Allocator) ![]u21 {
        @panic("TODO: implement");
    }
};
```

### Implementation Steps

1. **Define the struct** with `sorted: []const u21` field

2. **Implement `init()`**: Just wrap the provided slice (no allocation)

3. **Stub `fromInts()`**: Will convert i32 array to u21 array, sort it, return RuneSet

4. **Stub `fromKeys()`**: Will extract keys from map, sort them, return RuneSet

5. **Stub `contains()`**: Will use binary search to check membership

6. **Stub `size()`**: Return length of sorted slice

7. **Stub `filter()`**: Will allocate new slice, filter elements, return new RuneSet

8. **Stub `toArray()`**: Will allocate and copy the sorted slice

## File Location

Create the file at: `src/util/runeset.zig`

## Dependencies

This is a foundation module with no dependencies on other project modules. It only uses:
- `std.mem.Allocator` for memory management
- `std` library functions for sorting and searching (when implemented)

## Success Criteria

- [ ] File `src/util/runeset.zig` exists
- [ ] `RuneSet` struct defined with `sorted: []const u21` field
- [ ] `init()` constructor method defined
- [ ] `fromInts()` factory constructor defined
- [ ] `fromKeys()` factory constructor defined
- [ ] `contains()` method defined
- [ ] `size()` method defined
- [ ] `filter()` method defined
- [ ] `toArray()` method defined
- [ ] All methods stub with `@panic("TODO: implement")`
- [ ] File compiles without errors
- [ ] Proper imports (`const std = @import("std");`)
- [ ] Proper visibility (`pub` for public API)

## Validation Commands

After creating the file, verify it compiles:

```bash
zig build
```

Should succeed with no compilation errors (warnings are acceptable for unused parameters in stubs).

## Common Pitfalls

1. **Wrong Type**: Don't use `u8` for runes - use `u21` to represent full Unicode range
2. **Mutability**: Use `[]const u21` not `[]u21` - the slice should be immutable
3. **Early Implementation**: Don't implement binary search or sorting yet - just stub everything
4. **Missing Allocator**: Remember that `fromInts()`, `fromKeys()`, `filter()`, and `toArray()` need allocators
5. **Method Syntax**: First parameter should be `self: RuneSet` or `self: *RuneSet` depending on whether mutation is needed
6. **Error Handling**: Factory methods that allocate should return `!RuneSet` (error union)
7. **Function Pointer Syntax**: For the filter predicate, use `*const fn(u21) bool` not just `fn(u21) bool`

## Notes

- This struct is intentionally simple - it's just a wrapper around a sorted slice
- The real complexity (binary search, sorting) will be implemented in later tasks
- The `init()` method does NOT own or copy the slice - it just references it
- Factory constructors (`fromInts`, `fromKeys`) DO allocate and own their slices
- This is a read-only data structure - no mutation methods
- The filter operation creates a NEW RuneSet rather than modifying the existing one

## Next Steps

After this task is complete, you can:
1. Implement the actual logic for each method (Task 02b)
2. Add unit tests for RuneSet (Task 02c)
3. Use RuneSet in other modules that need efficient character set operations
