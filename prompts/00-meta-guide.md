# Meta Guide: ENS Normalize Zig Port - End-to-End Implementation

## Project Overview

This project is a **complete port of the Go ENS normalize library to Zig**. We are implementing the ENSIP-15 specification for Ethereum Name Service (ENS) name normalization, which handles Unicode normalization, emoji sequences, script validation, and confusable detection.

**Source**: [go-ens-normalize](https://github.com/adraffy/go-ens-normalize) reference implementation
**Target**: Zig implementation at `/Users/williamcory/z-ens-normalize`
**Goal**: 100% feature parity with passing tests

---

## What Are These Prompts?

The `prompts/` directory contains **19 detailed implementation guides** (tasks 01-19). Each prompt file is a **complete specification** for implementing one component of the system. They include:

- Complete Go reference code to port
- Step-by-step implementation guidance
- Type mappings (Go → Zig)
- Success criteria checklist
- Validation commands
- Common pitfalls to avoid

**Important**: These prompts describe **stub implementations** first. The goal is to get everything compiling with `@panic("TODO")` or `unreachable` stubs, then implement the actual logic.

---

## Implementation Strategy

### Stage 1: Skeleton Setup (Tasks 01-19)
**Goal**: Get entire project compiling with failing tests

This stage creates the project structure, type definitions, and test infrastructure with all logic stubbed out. When complete:
- ✅ `zig build` succeeds (no compile errors)
- ✅ `zig build test` runs (all tests FAIL with unreachable/panic)
- ✅ All files exist with correct signatures

### Stage 2: Implementation (Following dependency order)
**Goal**: Implement actual logic to make tests pass

This stage fills in the stubs with real implementations. Tests should progressively pass as components are completed.

---

## Execution Order

### Phase 1: Foundation (Parallel - 8 agents)

Execute these **in parallel** - they have no dependencies on each other:

```bash
# Agent 1: Task 01
prompts/01-util-decoder.md

# Agent 2: Task 02
prompts/02-util-runeset.md

# Agent 3: Task 03
prompts/03-nf-types.md

# Agent 4: Task 04
prompts/04-copy-binaries.md

# Agent 5: Task 05
prompts/05-copy-test-data.md

# Agent 6: Task 06
prompts/06-ensip15-types.md

# Agent 7: Task 07
prompts/07-error-types.md

# Agent 8: Task 08
prompts/08-json-parser.md
```

**Validation**: After Phase 1, verify:
```bash
zig build  # Should succeed
ls src/util/ src/nf/ src/ensip15/ test-data/  # All exist
```

---

### Phase 2: Core Implementation (Parallel - 8 agents)

Execute these **in parallel** after Phase 1 completes:

```bash
# Agent 1: Task 09 (depends on: 01, 02, 03, 04)
prompts/09-nf-init.md

# Agent 2: Task 10 (depends on: 09)
prompts/10-nf-normalization.md

# Agent 3: Task 11 (depends on: 01, 02, 04, 06, 07)
prompts/11-ensip15-init.md

# Agent 4: Task 12 (depends on: 06)
prompts/12-ensip15-utils.md

# Agent 5: Task 13 (depends on: 11, 12, 10)
prompts/13-ensip15-normalize.md

# Agent 6: Task 14 (depends on: 13)
prompts/14-ensip15-beautify.md

# Agent 7: Task 15 (depends on: 11, 13, 14, 07)
prompts/15-root-module.md

# Agent 8: Task 16 (depends on: all above)
prompts/16-build-structure.md
```

**Validation**: After Phase 2, verify:
```bash
zig build  # Should succeed
zig build --help  # Shows available build steps
```

---

### Phase 3: Test Infrastructure (Parallel - 3 agents)

Execute these **in parallel** after Phase 2 completes:

```bash
# Agent 1: Task 17 (depends on: 05, 08, 09, 10)
prompts/17-nf-tests.md

# Agent 2: Task 18 (depends on: 05, 08, 11, 13)
prompts/18-ensip15-tests.md

# Agent 3: Task 19 (validation checklist)
prompts/19-validation-checklist.md
```

**Validation**: After Phase 3, verify:
```bash
zig build test  # Runs tests (they FAIL - expected)
```

---

### Phase 4: Actual Implementation (Sequential by module)

Now implement the actual logic (no stubs). Follow this order:

#### Step 1: Decoder Implementation
```bash
# Implement src/util/decoder.zig
# - readBit(), readUnary(), readBinary()
# - ReadUnsigned(), ReadSortedAscending(), etc.
# Reference: go-ens-normalize/util/decoder.go
```

**Validation**: No tests yet, but should be callable without panicking.

#### Step 2: RuneSet Implementation
```bash
# Implement src/util/runeset.zig
# - Binary search in contains()
# - Filter, toArray methods
# Reference: go-ens-normalize/util/runeset.go
```

**Validation**: No tests yet, but decoder depends on this.

#### Step 3: NF Initialization
```bash
# Implement src/nf/nf.zig init()
# - Decode nf.bin using decoder
# - Populate decomps, recomps, ranks maps
# Reference: go-ens-normalize/nf/nf.go lines 53-96
```

**Validation**:
```bash
zig build test  # NF tests may start passing
```

#### Step 4: NF Normalization
```bash
# Implement src/nf/nf.zig NFC/NFD methods
# - decomposed() function
# - composePair() for Hangul
# - Packer struct for canonical ordering
# - composedFromPacked()
# Reference: go-ens-normalize/nf/nf.go lines 98-246
```

**Validation**:
```bash
zig build test  # NF tests should PASS
```

#### Step 5: ENSIP15 Data Loading
```bash
# Implement src/ensip15/ensip15.zig init()
# - decodeNamedCodepoints()
# - decodeMapped()
# - decodeGroups() (from groups.go)
# - decodeEmojis() (from emojis.go)
# - decodeWholes() (from wholes.go)
# Reference: go-ens-normalize/ensip15/*.go
```

**Note**: You'll need to port additional Go files:
- `groups.go` → group decoding logic
- `emojis.go` → emoji tree construction
- `wholes.go` → confusable detection
- `output.go` → tokenization

#### Step 6: ENSIP15 Utilities
```bash
# Implement src/ensip15/utils.zig
# - split(), join()
# - safeCodepoint(), toHexSequence()
# - isAscii(), uniqueRunes(), compareRunes()
# Reference: go-ens-normalize/ensip15/utils.go
```

#### Step 7: ENSIP15 Validation
```bash
# Implement validation functions in ensip15.zig
# - checkLeadingUnderscore()
# - checkLabelExtension()
# - checkCombiningMarks()
# - checkFenced()
# - checkValidLabel()
# Reference: go-ens-normalize/ensip15/ensip15.go lines 223-329
```

#### Step 8: ENSIP15 Normalization Pipeline
```bash
# Implement transform() and normalize()
# - outputTokenize() (tokenize to Text/Emoji)
# - determineGroup() (script detection)
# - checkGroup() (CM validation)
# - checkWhole() (confusable detection)
# Reference: go-ens-normalize/ensip15/ensip15.go lines 142-221
```

**Validation**:
```bash
zig build test  # ENSIP15 tests should start passing
```

#### Step 9: Final Features
```bash
# Implement beautify() and normalizeFragment()
# Reference: go-ens-normalize/ensip15/ensip15.go lines 158-195
```

**Validation**:
```bash
zig build test  # ALL tests should PASS
```

---

## Dependency Graph

```
Phase 1 (Foundation)
├── 01 (decoder) ─────────┐
├── 02 (runeset) ─────────┼────┐
├── 03 (nf-types) ────────┤    │
├── 04 (binaries) ────────┤    │
├── 05 (test-data) ───────┤    │
├── 06 (ensip15-types) ───┤    │
├── 07 (errors) ──────────┤    │
└── 08 (json-parser) ─────┘    │
                               │
Phase 2 (Core)                 │
├── 09 (nf-init) ←─────────────┤
├── 10 (nf-norm) ←─────────┐   │
├── 11 (ensip15-init) ←────┼───┘
├── 12 (utils) ←───────────┤
├── 13 (normalize) ←───────┼───┐
├── 14 (beautify) ←────────┤   │
├── 15 (root) ←────────────┼───┘
└── 16 (build) ←───────────┘
                               │
Phase 3 (Tests)                │
├── 17 (nf-tests) ←────────────┤
├── 18 (ensip15-tests) ←───────┤
└── 19 (validation) ←──────────┘
```

---

## How to Use These Prompts with Agents

### For Each Task:

1. **Read the prompt file** completely
2. **Check dependencies** are satisfied (previous tasks done)
3. **Follow the implementation guidance** exactly
4. **Use the Go reference code** as your guide
5. **Verify success criteria** checklist
6. **Run validation commands** to confirm

### Agent Invocation Pattern:

```bash
# Example for Task 01
<agent>
  Read and follow the complete instructions in prompts/01-util-decoder.md

  Your goal:
  - Create src/util/decoder.zig
  - Define Decoder struct with all fields
  - Define all public methods with correct signatures
  - Stub all methods with @panic("TODO: implement")
  - Ensure file compiles

  Reference code is included in the prompt.
  Success criteria and validation commands are at the end.

  Do not implement logic yet, only create stubs.
</agent>
```

---

## Stage 1 Completion Criteria

After executing all Phase 1-3 tasks (01-19), you should have:

### ✅ File Structure
```
z-ens-normalize/
├── prompts/
│   ├── 00-meta-guide.md (this file)
│   ├── 01-util-decoder.md
│   ├── ... (02-18)
│   └── 19-validation-checklist.md
├── src/
│   ├── util/
│   │   ├── decoder.zig (stubbed)
│   │   └── runeset.zig (stubbed)
│   ├── nf/
│   │   ├── nf.zig (stubbed)
│   │   └── nf.bin (binary data)
│   ├── ensip15/
│   │   ├── types.zig (stubbed)
│   │   ├── errors.zig (complete)
│   │   ├── ensip15.zig (stubbed)
│   │   ├── utils.zig (stubbed)
│   │   └── spec.bin (binary data)
│   └── root.zig (public API)
├── tests/
│   ├── json_parser.zig (stubbed)
│   ├── nf_test.zig (runs, fails)
│   └── ensip15_test.zig (runs, fails)
├── test-data/
│   ├── ensip15-tests.json
│   └── nf-tests.json
├── build.zig (complete)
└── README.md
```

### ✅ Build Status
```bash
$ zig build
Build succeeded

$ zig build test
Test [1/2] test.nf... FAIL (reached unreachable)
Test [2/2] test.ensip15... FAIL (reached unreachable)

$ zig build --help
Steps:
  install (default): Copy artifacts to prefix path
  test: Run all tests
  copy-test-data: Copy test JSON files
```

### ✅ Code Quality
- All public functions have `///` doc comments
- All stubs use `@panic("TODO: implement")` or `unreachable`
- Types are consistent across modules
- No compile errors or warnings

---

## Stage 2: Full Implementation

Once Stage 1 is complete, follow **Phase 4** (Actual Implementation) above.

### Implementation Tips:

1. **Start with decoder** - everything depends on it
2. **Test incrementally** - run `zig build test` after each module
3. **Reference Go code** - it's your specification
4. **Watch test output** - tests will progressively pass
5. **Use allocators correctly** - pass explicitly, free when done
6. **Handle errors properly** - use `!T` return types

### Expected Test Progression:

```
After decoder + runeset: 0 tests pass
After NF init: 0 tests pass (need NFC/NFD)
After NF normalization: ~50% NF tests pass
After ENSIP15 init: 0 ENSIP15 tests pass (need validation)
After utilities: 0 new tests pass
After validation: ~30% ENSIP15 tests pass
After normalize(): ~70% ENSIP15 tests pass
After beautify(): 100% tests pass ✅
```

---

## Final Validation

Run the complete validation from Task 19:

```bash
# Run validation script
bash prompts/19-validation-checklist.md  # (extract script section)

# Or manually:
zig build
zig build test
ls -R src/ tests/ test-data/

# Expected: All tests PASS
```

---

## Success Criteria - E2E

The port is **complete** when:

- ✅ `zig build` succeeds with no errors/warnings
- ✅ `zig build test` shows 100% tests passing
- ✅ All functionality from Go library is ported
- ✅ Public API matches design (normalize, beautify, etc.)
- ✅ Binary spec files are embedded and decoded correctly
- ✅ All test cases from reference implementation pass

---

## Additional Go Files to Port

Beyond the 19 prompts, you'll need to port these Go files for full implementation:

1. **ensip15/groups.go** - Script group validation logic
2. **ensip15/emojis.go** - Emoji tree and sequence handling
3. **ensip15/wholes.go** - Whole-script confusable detection
4. **ensip15/output.go** - Output tokenization (Text/Emoji tokens)

These are referenced in the prompts but not fully specified. Use the Go code as your specification.

---

## Getting Help

Each prompt file includes:
- **Common Pitfalls** section - avoid these mistakes
- **Validation Commands** section - verify your work
- **Success Criteria** section - checklist for completion

If stuck:
1. Re-read the prompt file carefully
2. Check the Go reference code
3. Verify dependencies are implemented
4. Run `zig build` to check for compile errors
5. Check types match between modules

---

## Meta Prompt for Agents

**Recommended agent prompt template:**

```
You are implementing Task [XX] of the ENS normalize Zig port.

Read the complete instructions in: prompts/[XX]-[name].md

Your goal is to [stage 1: create stubs | stage 2: implement logic] for [component name].

Follow these steps:
1. Read the entire prompt file
2. Verify dependencies (tasks [list]) are complete
3. Study the Go reference code provided
4. Implement as instructed (stubs or full logic)
5. Verify all success criteria
6. Run validation commands

Report:
- Files created/modified
- Success criteria checklist status
- Validation command results
- Any issues encountered

Do not deviate from the prompt instructions.
```

---

## Project Context

**Why this project?**
ENS (Ethereum Name Service) requires robust Unicode normalization to prevent:
- Homograph attacks (confusable characters)
- Invalid names (disallowed characters)
- Inconsistent display (presentation variations)

**Why Zig?**
- Memory safety without garbage collection
- Explicit allocator control
- C interop for embeddings
- Fast compilation and runtime

**Why port from Go?**
The Go implementation by @adraffy is the reference implementation with:
- Complete ENSIP-15 compliance
- Comprehensive test suite
- Optimized binary spec format
- Proven correctness

---

## Quick Start

```bash
# Stage 1: Create skeleton (all 19 tasks with stubs)
# Deploy agents for tasks 01-08 in parallel
# Then 09-16 in parallel
# Then 17-19 in parallel
# Result: zig build succeeds, tests fail

# Stage 2: Implement logic (follow Phase 4 order)
# Implement decoder → runeset → NF → ENSIP15
# Result: zig build test passes

# Done!
```

---

**This meta guide should be your roadmap. Follow it exactly for E2E implementation success.**
