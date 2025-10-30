# Task 10: Implement NFC/NFD Normalization Methods

## Goal

Port the Unicode normalization algorithms (NFC and NFD) with special Hangul handling from Go to Zig. These are the core public methods that transform Unicode text into normalized forms. This task implements the complete normalization pipeline including decomposition, canonical ordering, and recomposition.

## Go Reference Code

From `/Users/williamcory/z-ens-normalize/go-ens-normalize/nf/nf.go` lines 98-246:

```go
func (nf *NF) composePair(a, b rune) rune {
	if a >= L0 && a < L1 && b >= V0 && b < V1 {
		return S0 + (a-L0)*N_COUNT + (b-V0)*T_COUNT
	} else if isHangul(a) && b > T0 && b < T1 && (a-S0)%T_COUNT == 0 {
		return a + (b - T0)
	} else {
		if recomp, ok := nf.recomps[a]; ok {
			if cp, ok := recomp[b]; ok {
				return cp
			}
		}
		return NONE
	}
}

type Packer struct {
	nf    *NF
	buf   []rune
	check bool
}

func (p *Packer) add(cp rune) {
	if cc, ok := p.nf.ranks[cp]; ok {
		p.check = true
		cp |= rune(cc) << SHIFT
	}
	p.buf = append(p.buf, cp)
}

func (p *Packer) fixOrder() {
	if !p.check {
		return
	}
	v := p.buf
	prev := unpackCC(v[0])
	for i := 1; i < len(v); i++ {
		cc := unpackCC(v[i])
		if cc == 0 || prev <= cc {
			prev = cc
			continue
		}
		j := i - 1
		for {
			v[j+1], v[j] = v[j], v[j+1]
			if j == 0 {
				break
			}
			j--
			prev = unpackCC(v[j])
			if prev <= cc {
				break
			}
		}
		prev = unpackCC(v[i])
	}
}

func (nf *NF) decomposed(cps []rune) []rune {
	p := Packer{nf: nf}
	var buf []rune
	for _, cp0 := range cps {
		cp := cp0
		for {
			if cp < 0x80 {
				p.buf = append(p.buf, cp)
			} else if isHangul(cp) {
				sIndex := cp - S0
				lIndex := sIndex / N_COUNT
				vIndex := (sIndex % N_COUNT) / T_COUNT
				tIndex := sIndex % T_COUNT
				p.add(L0 + lIndex)
				p.add(V0 + vIndex)
				if tIndex > 0 {
					p.add(T0 + tIndex)
				}
			} else {
				if decomp, ok := nf.decomps[cp]; ok {
					buf = append(buf, decomp...)
				} else {
					p.add(cp)
				}
			}
			if len(buf) == 0 {
				break
			}
			last := len(buf) - 1
			cp = buf[last]
			buf = buf[:last]
		}
	}

	p.fixOrder()
	return p.buf
}

func (nf *NF) composedFromPacked(packed []rune) []rune {
	cps := make([]rune, 0, len(packed))
	var stack []rune
	prevCp := NONE
	var prevCc byte
	for _, p := range packed {
		cc := unpackCC(p)
		cp := unpackCP(p)
		if prevCp == NONE {
			if cc == 0 {
				prevCp = cp
			} else {
				cps = append(cps, cp)
			}
		} else if prevCc > 0 && prevCc >= cc {
			if cc == 0 {
				cps = append(cps, prevCp)
				cps = append(cps, stack...)
				stack = nil
				prevCp = cp
			} else {
				stack = append(stack, cp)
			}
			prevCc = cc
		} else {
			composed := nf.composePair(prevCp, cp)
			if composed != NONE {
				prevCp = composed
			} else if prevCc == 0 && cc == 0 {
				cps = append(cps, prevCp)
				prevCp = cp
			} else {
				stack = append(stack, cp)
				prevCc = cc
			}
		}
	}
	if prevCp != NONE {
		cps = append(cps, prevCp)
		cps = append(cps, stack...)
	}
	return cps
}

func (nf *NF) NFD(cps []rune) []rune {
	v := nf.decomposed(cps)
	for i, x := range v {
		v[i] = unpackCP(x)
	}
	return v
}
func (nf *NF) NFC(cps []rune) []rune {
	return nf.composedFromPacked(nf.decomposed(cps))
}
```

## Implementation Guidance

### Understanding Unicode Normalization

Unicode provides multiple ways to represent the same text. For example, "é" can be represented as:
- A single precomposed character (U+00E9)
- A decomposed sequence: "e" (U+0065) + combining acute accent (U+0301)

Normalization ensures consistent representation:

#### NFD (Canonical Decomposition)
- Decomposes all characters to their canonical decomposed form
- Example: é (U+00E9) → e (U+0065) + ´ (U+0301)
- Process: decompose + canonical ordering

#### NFC (Canonical Composition)
- Decomposes then recomposes where possible
- Example: e + ´ → é (most compact form)
- Process: decompose + canonical ordering + recompose

### The Normalization Pipeline

```
Input codepoints
    ↓
decomposed() - Recursive decomposition with Hangul special handling
    ↓
Packed values (CP + CC in single u32)
    ↓
fixOrder() - Canonical ordering by combining class
    ↓
For NFC: composedFromPacked() - Recompose where allowed
    ↓
For NFD: Unpack to plain codepoints
    ↓
Output codepoints
```

### Algorithm Details

#### 1. composePair() - Attempt to Compose Two Codepoints

This method attempts to compose two codepoints into a single codepoint:

**Hangul Composition (Algorithmic)**:
1. **L + V → LV syllable**: Leading consonant + Vowel → Base syllable
   - Check: `a` in L range, `b` in V range
   - Formula: `S0 + (a-L0)*N_COUNT + (b-V0)*T_COUNT`

2. **LV + T → LVT syllable**: Base syllable + Trailing consonant → Full syllable
   - Check: `a` is Hangul, `b` in T range, `a` is base syllable (divisible by T_COUNT)
   - Formula: `a + (b - T0)`

**General Composition (Table Lookup)**:
- Look up `a` in recomps map
- If found, look up `b` in nested map
- Return composed codepoint or NONE if no composition exists

**Zig Signature**:
```zig
fn composePair(self: *const NF, a: u21, b: u21) i32 {
    unreachable;
}
```

**Return Type**: `i32` to accommodate NONE (-1)

#### 2. Packer Struct - Decomposition Buffer with Combining Class

The Packer accumulates decomposed codepoints and tracks whether canonical ordering is needed:

**Fields**:
- `nf`: Pointer to NF instance (for accessing ranks)
- `buf`: ArrayList(i32) - holds packed values
- `check`: bool - true if any combining marks were added (ordering needed)

**Zig Definition**:
```zig
const Packer = struct {
    nf: *const NF,
    buf: std.ArrayList(i32),
    check: bool,

    fn add(self: *Packer, cp: u21) void {
        unreachable;
    }

    fn fixOrder(self: *Packer) void {
        unreachable;
    }
};
```

#### 3. Packer.add() - Add Codepoint with Combining Class

Adds a codepoint to the buffer, packing it with its combining class if present:

**Algorithm**:
1. Look up `cp` in `nf.ranks` map
2. If found:
   - Set `check = true` (ordering will be needed)
   - Pack: `cp = cp | (cc << SHIFT)` - OR the CC into upper bits
3. Append packed value to buffer

**Packing Format**: `[CC: 8 bits][CP: 24 bits]`

#### 4. Packer.fixOrder() - Canonical Ordering (Bubble Sort)

Reorders codepoints by their combining class to achieve canonical ordering:

**Why Needed**: Unicode requires combining marks to be in a specific order. For example, a base character followed by multiple diacritics must have those diacritics sorted by their combining class values.

**Algorithm**:
1. If `!check`, skip (no combining marks present)
2. Bubble sort by combining class using `unpackCC()`
3. Maintain stability: only swap if previous CC > current CC
4. Special handling: CC=0 (starter characters) are never reordered

**Zig Implementation**:
```zig
fn fixOrder(self: *Packer) void {
    if (!self.check) return;
    // Bubble sort implementation
    unreachable;
}
```

#### 5. decomposed() - Recursive Decomposition

The main decomposition method that handles all three cases: ASCII, Hangul, and table lookup:

**Algorithm**:
```
For each input codepoint cp0:
  cp = cp0
  Loop:
    Case 1: ASCII (cp < 0x80)
      - Add directly to packer (no decomposition needed)
      - Break loop

    Case 2: Hangul syllable (isHangul(cp))
      - Compute indices: sIndex, lIndex, vIndex, tIndex
      - Add L (leading consonant) via packer.add()
      - Add V (vowel) via packer.add()
      - If tIndex > 0: Add T (trailing consonant) via packer.add()
      - Break loop

    Case 3: Table lookup
      - If cp in decomps map:
        - Push decomposition sequence to buffer
        - Continue loop with last codepoint from buffer (recursive)
      - Else:
        - Add cp via packer.add()
        - Break loop

    If buffer empty: break
    Pop last codepoint from buffer
    Continue loop with popped value

After all codepoints processed:
  Call packer.fixOrder() for canonical ordering
  Return packer.buf
```

**Key Points**:
- Uses a temporary buffer for recursive decomposition
- Hangul decomposition is algorithmic (no table lookup)
- ASCII fast path (no lookup needed)
- Packer.add() handles combining class packing
- fixOrder() ensures canonical ordering

**Zig Signature**:
```zig
fn decomposed(self: *const NF, allocator: Allocator, cps: []const u21) ![]i32 {
    unreachable;
}
```

**Note**: This is an internal method that returns packed values (i32).

#### 6. composedFromPacked() - Composition with Blocking

Recomposes decomposed+packed codepoints while respecting blocking rules:

**Blocking Rules**:
- A combining mark blocks composition if it has the same or higher combining class than following marks
- Example: base + CC1 + CC1 → Cannot compose base with second CC1

**Algorithm**:
```
Initialize:
  cps = output array
  stack = combining marks that couldn't compose
  prevCp = NONE (no starter yet)
  prevCc = 0

For each packed value p:
  cc = unpackCC(p)
  cp = unpackCP(p)

  Case 1: No starter yet (prevCp == NONE)
    If cc == 0:
      prevCp = cp (found starter)
    Else:
      Append cp to output (orphan combining mark)

  Case 2: Blocking condition (prevCc > 0 && prevCc >= cc)
    If cc == 0:
      Flush prevCp and stack to output
      prevCp = cp (new starter)
    Else:
      Add cp to stack (blocked from composing)
    Update prevCc = cc

  Case 3: Try to compose
    composed = composePair(prevCp, cp)
    If composed != NONE:
      prevCp = composed (successful composition)
    Else if prevCc == 0 && cc == 0:
      Flush prevCp to output
      prevCp = cp (new starter, no composition)
    Else:
      Add cp to stack (failed to compose)
      prevCc = cc

Final flush:
  If prevCp != NONE:
    Append prevCp and stack to output

Return output
```

**Key Points**:
- Maintains a "starter" character that can be composed
- Tracks previous combining class to detect blocking
- Stack holds marks that couldn't compose
- Composition changes the starter in-place

**Zig Signature**:
```zig
fn composedFromPacked(self: *const NF, allocator: Allocator, packed: []const i32) ![]u21 {
    unreachable;
}
```

#### 7. NFD() - Public NFD Method

The public API for NFD normalization:

**Algorithm**:
```
1. Call decomposed(cps) to get packed values
2. Unpack each value: v[i] = unpackCP(v[i])
3. Return unpacked codepoints
```

**Zig Signature**:
```zig
pub fn nfd(self: *const NF, allocator: Allocator, cps: []const u21) ![]u21 {
    unreachable;
}
```

**Parameters**:
- `self`: Const pointer to NF instance
- `allocator`: Allocator for output slice
- `cps`: Input codepoint slice

**Returns**: `![]u21` - Error union of codepoint slice

#### 8. NFC() - Public NFC Method

The public API for NFC normalization:

**Algorithm**:
```
1. Call decomposed(cps) to get packed values
2. Call composedFromPacked() on the packed values
3. Return composed codepoints
```

**Zig Signature**:
```zig
pub fn nfc(self: *const NF, allocator: Allocator, cps: []const u21) ![]u21 {
    unreachable;
}
```

**Note**: This is a simple pipeline - the complexity is in the helper methods.

### Hangul Algorithmic Details

**Hangul Decomposition** (S → L + V + T):
```
Given Hangul syllable S:
  sIndex = S - S0
  lIndex = sIndex / N_COUNT
  vIndex = (sIndex % N_COUNT) / T_COUNT
  tIndex = sIndex % T_COUNT

  Result: L0+lIndex, V0+vIndex, [T0+tIndex if tIndex > 0]
```

**Hangul Composition** (L + V → LV or LV + T → LVT):
```
L + V → LV:
  result = S0 + (L-L0)*N_COUNT + (V-V0)*T_COUNT

LV + T → LVT:
  result = LV + (T - T0)
  (only if (LV - S0) % T_COUNT == 0, meaning it's a base syllable)
```

### Memory Management

**Allocator Usage**:
- All public methods (`nfd`, `nfc`) take an allocator parameter
- Internal methods (`decomposed`, `composedFromPacked`) also take allocator
- Packer struct should be initialized with allocator for its ArrayList
- Temporary buffers should be freed before returning
- Return values are allocated with the provided allocator (caller owns)

**Example Pattern**:
```zig
pub fn nfd(self: *const NF, allocator: Allocator, cps: []const u21) ![]u21 {
    var packed = try self.decomposed(allocator, cps);
    defer allocator.free(packed);

    var result = try allocator.alloc(u21, packed.len);
    for (packed, 0..) |p, i| {
        result[i] = unpackCP(p);
    }
    return result;
}
```

## File Location

Add all methods to: `/Users/williamcory/z-ens-normalize/src/nf/nf.zig`

These methods should be added to the existing NF struct and as helper functions/structs in the same file.

## Dependencies

### Required Before This Task

1. **Task 03**: NF struct defined with all fields
   - Hangul constants (S0, L0, V0, T0, etc.)
   - Packing constants (SHIFT, MASK, NONE)
   - Helper functions (isHangul, unpackCC, unpackCP)

2. **Task 09**: NF.init() method implemented
   - NF struct can be instantiated with populated data
   - decomps, recomps, ranks maps are filled

### Imports Needed

```zig
const std = @import("std");
const Allocator = std.mem.Allocator;
// RuneSet and other utils already imported from Task 03
```

## Success Criteria

- [ ] `composePair()` method defined with signature: `fn composePair(self: *const NF, a: u21, b: u21) i32`
- [ ] Packer struct defined with fields: `nf: *const NF`, `buf: std.ArrayList(i32)`, `check: bool`
- [ ] Packer.add() method defined with signature: `fn add(self: *Packer, cp: u21) void`
- [ ] Packer.fixOrder() method defined with signature: `fn fixOrder(self: *Packer) void`
- [ ] `decomposed()` method defined with signature: `fn decomposed(self: *const NF, allocator: Allocator, cps: []const u21) ![]i32`
- [ ] `composedFromPacked()` method defined with signature: `fn composedFromPacked(self: *const NF, allocator: Allocator, packed: []const i32) ![]u21`
- [ ] `nfd()` public method defined with signature: `pub fn nfd(self: *const NF, allocator: Allocator, cps: []const u21) ![]u21`
- [ ] `nfc()` public method defined with signature: `pub fn nfc(self: *const NF, allocator: Allocator, cps: []const u21) ![]u21`
- [ ] All methods stub with `unreachable` (no actual implementation yet)
- [ ] File compiles without errors
- [ ] `zig build` succeeds

## Validation Commands

After implementation, verify the code compiles:

```bash
zig build
```

This should succeed without errors.

## Common Pitfalls

### Method Signatures

**Correct Order**:
```zig
pub fn nfd(self: *const NF, allocator: Allocator, cps: []const u21) ![]u21
//         ^^^^^ self first  ^^^^^^^^^ then allocator
```

**Not**:
```zig
pub fn nfd(allocator: Allocator, self: *const NF, cps: []const u21) ![]u21
// Wrong order!
```

### Return Types

- `composePair()`: Returns `i32` (to accommodate NONE = -1)
- `decomposed()`: Returns `![]i32` (packed values, error union)
- `composedFromPacked()`: Returns `![]u21` (unpacked codepoints, error union)
- `nfd()`, `nfc()`: Return `![]u21` (error union of codepoint slice)

### Const Correctness

All methods on NF should take `self: *const NF` (const pointer) because they don't modify the NF instance - they only read from it.

### Packer Initialization

The Packer struct needs to be initialized with an ArrayList:
```zig
var packer = Packer{
    .nf = self,
    .buf = std.ArrayList(i32).init(allocator),
    .check = false,
};
defer packer.buf.deinit();
```

### Don't Implement Logic Yet

For now, all methods should just stub with `unreachable`:
```zig
fn composePair(self: *const NF, a: u21, b: u21) i32 {
    unreachable;
}
```

This allows the signatures to be defined and tested for compilation without implementing the complex logic.

### Hangul Constants Dependency

Ensure that Task 03 constants are available:
- S0, L0, V0, T0
- L_COUNT, V_COUNT, T_COUNT, N_COUNT
- L1, V1, T1, S1
- isHangul() function

These will be used in composePair() and decomposed() when actually implemented.

### Packed Value Handling

Remember the packing format:
```
i32 value: [CC: 8 bits][CP: 24 bits]

Pack:   packed = cp | (cc << SHIFT)
Unpack: cp = packed & MASK
        cc = (packed >> SHIFT) & 0xFF
```

Use unpackCC() and unpackCP() helper functions from Task 03.

## Implementation Strategy

1. **Review Task 03 output** to ensure all constants and helpers are in place
2. **Define Packer struct** near the top of the file (before NF methods)
3. **Add Packer methods** (add, fixOrder) as stubs
4. **Add NF helper methods** (composePair, decomposed, composedFromPacked) as stubs
5. **Add public methods** (nfd, nfc) as stubs
6. **Verify compilation** with `zig build`
7. **Document** with clear comments about what each method will do

## Next Steps

After completing this task (stubs only):
- **Task 11**: Implement composePair() logic
- **Task 12**: Implement Packer.add() and fixOrder() logic
- **Task 13**: Implement decomposed() logic
- **Task 14**: Implement composedFromPacked() logic
- **Task 15**: Implement nfd() and nfc() logic
- **Task 16**: Add test cases for normalization

## Additional Context

### Why Two-Phase Normalization?

The decomposed → packed → ordered → composed pipeline might seem complex, but it's necessary:

1. **Decomposition Phase**: Break down all precomposed characters
2. **Packing Phase**: Attach combining classes to track ordering requirements
3. **Ordering Phase**: Sort by combining class (canonical ordering)
4. **Composition Phase**: Rebuild precomposed forms where allowed

This ensures:
- Consistent representation (same text → same bytes)
- Correct combining mark order
- Maximum compatibility across systems

### Performance Considerations

**Fast Paths**:
- ASCII characters (< 0x80) skip decomposition lookup
- Quick check set (from NF struct) can skip already-normalized text
- Hangul uses algorithmic decomp/comp (no table lookup)

**Memory Usage**:
- Packer uses single ArrayList (not multiple buffers)
- Packed values reduce memory (32-bit vs two separate values)
- Reuse allocator-provided memory

### Unicode Stability

Once a composition is defined in Unicode, it cannot change. The exclusions set (from Task 03) contains codepoints that should NOT be composed even if a composition exists in the recomps table. This maintains backward compatibility with older Unicode versions.

### Canonical vs Compatibility

This implementation handles **canonical** normalization (NFC/NFD). There are also compatibility forms (NFKC/NFKD) which perform additional transformations. For ENS normalization, only NFC is used.

### Testing Approach

When implementation begins (later tasks), test with:
- Empty strings
- ASCII-only strings (no normalization needed)
- Precomposed characters (café)
- Decomposed characters (cafe + combining accents)
- Hangul syllables
- Mixed scripts
- Extreme combining mark sequences

The Unicode Consortium provides official test files for normalization validation.
