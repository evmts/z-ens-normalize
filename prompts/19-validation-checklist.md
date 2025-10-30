# Task 19: Final Validation Checklist

## Goal

Provide a comprehensive checklist to verify all prompt tasks (01-18) are complete and the project is ready for implementation. This validation ensures the entire skeleton codebase compiles, all tests are in place (though failing as expected), and the build system is properly configured.

## Overview

This checklist validates that:
- All source files exist and compile successfully
- All test files exist and run (failing with unreachable/panic as expected)
- Binary data files are present and accessible
- Build system is fully configured
- Project structure matches the design
- Code is ready for implementation phase

## Validation Categories

### A. File Structure

Verify all required files and directories exist:

- [ ] **Prompts Directory**: All 19 prompt files exist (01-18 plus this one)
  - `prompts/01-project-setup.md`
  - `prompts/02-binary-data.md`
  - `prompts/03-decoder.md`
  - `prompts/04-runeset.md`
  - `prompts/05-nf-core.md`
  - `prompts/06-ensip15-types.md`
  - `prompts/07-ensip15-errors.md`
  - `prompts/08-ensip15-core.md`
  - `prompts/09-ensip15-utils.md`
  - `prompts/10-public-api.md`
  - `prompts/11-json-parser.md`
  - `prompts/12-nf-tests.md`
  - `prompts/13-ensip15-tests.md`
  - `prompts/14-build-system.md`
  - `prompts/15-integration-tests.md`
  - `prompts/16-documentation.md`
  - `prompts/17-examples.md`
  - `prompts/18-ci-setup.md`
  - `prompts/19-validation-checklist.md`

- [ ] **Source Directories**: All src/ subdirectories exist
  - `src/util/` (utility modules)
  - `src/nf/` (normalization)
  - `src/ensip15/` (ENSIP-15 implementation)

- [ ] **Binary Files**: Data files copied and present
  - `src/ensip15/spec.bin` (ENSIP-15 specification data)
  - `src/nf/nf.bin` (normalization form data)

- [ ] **Test Data**: JSON test files copied
  - `test-data/ensip15-tests.json` (ENSIP-15 test cases)
  - `test-data/nf-tests.json` (normalization test cases)

- [ ] **Test Directory**: tests/ directory exists with test files

### B. Source Files

Verify all source files exist and compile (with stubs):

- [ ] **src/util/decoder.zig**: Stream decoder utilities
  - Contains `StreamDecoder` type
  - Has `readByte()`, `readArray()`, `readBranching()` stubs
  - Compiles without errors
  - All stubs use `@panic("TODO: ...")` or `unreachable`

- [ ] **src/util/runeset.zig**: Rune set data structure
  - Contains `RuneSet` type
  - Has `contains()`, `fromArray()`, `fromRange()` stubs
  - Compiles without errors
  - All stubs use `@panic("TODO: ...")` or `unreachable`

- [ ] **src/nf/nf.zig**: Normalization form implementation
  - Contains `NF_DATA` constant for binary data
  - Has `nfd()` and `nfc()` function stubs
  - Compiles without errors
  - All stubs use `@panic("TODO: ...")` or `unreachable`

- [ ] **src/ensip15/types.zig**: ENSIP-15 type definitions
  - Contains `Label`, `DisallowedSequence`, `Token`, `TokenType` types
  - No stubs needed (pure type definitions)
  - Compiles without errors

- [ ] **src/ensip15/errors.zig**: ENSIP-15 error types
  - Contains `ENSIP15Error` error set
  - Defines all error variants (DisallowedCharacter, InvalidLabel, etc.)
  - No stubs needed (pure error definitions)
  - Compiles without errors

- [ ] **src/ensip15/ensip15.zig**: Core ENSIP-15 logic
  - Contains `SPEC_DATA` constant for binary data
  - Has `normalize()`, `beautify()`, `isNormalized()` stubs
  - Has `split()`, `parseTokens()`, `processLabel()` helper stubs
  - Compiles without errors
  - All stubs use `@panic("TODO: ...")` or `unreachable`

- [ ] **src/ensip15/utils.zig**: ENSIP-15 utility functions
  - Has `isValidCodepoint()`, `getEmojiSequence()` stubs
  - Compiles without errors
  - All stubs use `@panic("TODO: ...")` or `unreachable`

- [ ] **src/root.zig**: Public API exports
  - Exports main types: `Label`, `DisallowedSequence`, `Token`, `TokenType`
  - Exports errors: `ENSIP15Error`
  - Exports functions: `normalize`, `beautify`, `isNormalized`
  - Compiles without errors
  - Proper documentation comments (///) for public API

### C. Test Files

Verify all test files exist and run (failing as expected):

- [ ] **tests/json_parser.zig**: JSON test data parser
  - Contains `NFTest`, `ENSIP15Test` types
  - Has `parseNFTests()`, `parseENSIP15Tests()` stubs
  - Compiles without errors
  - All stubs use `@panic("TODO: ...")` or `unreachable`

- [ ] **tests/nf_test.zig**: Normalization tests
  - Contains `test "NF: Load test data"` stub
  - Contains `test "NF: Run all NFC/NFD tests"` stub
  - Compiles without errors
  - Tests run but fail with unreachable/panic (expected)
  - No actual implementation yet

- [ ] **tests/ensip15_test.zig**: ENSIP-15 tests
  - Contains `test "ENSIP15: Load test data"` stub
  - Contains `test "ENSIP15: Normalize valid names"` stub
  - Contains `test "ENSIP15: Reject invalid names"` stub
  - Contains `test "ENSIP15: Beautify names"` stub
  - Compiles without errors
  - Tests run but fail with unreachable/panic (expected)
  - No actual implementation yet

### D. Build System

Verify build.zig is properly configured:

- [ ] **Basic Build**: `zig build` succeeds
  - No compile errors
  - All source files compile
  - Exit code: 0

- [ ] **Test Build**: `zig build test` runs
  - Test executable compiles
  - Tests execute (fail expected)
  - Shows test failures with unreachable/panic messages

- [ ] **Copy Test Data**: `zig build copy-test-data` works
  - Copies JSON files from Go repo to test-data/
  - Creates test-data/ directory if needed
  - Reports successful copy

- [ ] **Build Help**: `zig build --help` shows all steps
  - Shows default build step
  - Shows test step
  - Shows copy-test-data step
  - Lists all available build options

- [ ] **Build Configuration**:
  - Library module properly configured
  - Test module properly configured
  - Binary data files embedded correctly
  - Dependencies configured (if any)

### E. Code Quality

Verify code meets quality standards:

- [ ] **Documentation**: All public functions have doc comments
  - Use `///` for documentation comments
  - Describe parameters and return values
  - Include examples where appropriate
  - Public API fully documented in src/root.zig

- [ ] **Stub Quality**: All stubs use proper patterns
  - Use `@panic("TODO: implement X")` for functions to be implemented
  - Use `unreachable` for code paths that should never execute
  - No placeholder implementations (e.g., returning dummy values)
  - Clear TODO messages describing what needs implementation

- [ ] **No Premature Implementation**: Only stubs present
  - No actual logic implemented yet
  - No data structure implementations
  - No algorithm implementations
  - Just type definitions, stubs, and structure

- [ ] **Type Consistency**: Types match between modules
  - Function signatures match declarations
  - Import/export types are consistent
  - Error types used consistently
  - Allocator patterns consistent (`allocator: std.mem.Allocator` first param)

- [ ] **Allocator Patterns**: Memory management conventions
  - Allocator as first parameter in functions that allocate
  - Consistent parameter naming: `allocator`
  - Return types use error unions for allocation failures
  - ArrayList and other collections properly initialized

## Validation Commands

Run these commands to validate the complete setup:

```bash
#!/bin/bash

echo "=== File Structure Validation ==="

# Check prompts directory
echo "Checking prompts/ directory..."
PROMPT_COUNT=$(ls -1 prompts/*.md 2>/dev/null | wc -l)
echo "Found $PROMPT_COUNT prompt files (expected: 19)"
[ $PROMPT_COUNT -eq 19 ] && echo "✓ All prompts present" || echo "✗ Missing prompt files"

# Check source directories
echo -e "\nChecking src/ directories..."
[ -d "src/util" ] && echo "✓ src/util/ exists" || echo "✗ src/util/ missing"
[ -d "src/nf" ] && echo "✓ src/nf/ exists" || echo "✗ src/nf/ missing"
[ -d "src/ensip15" ] && echo "✓ src/ensip15/ exists" || echo "✗ src/ensip15/ missing"

# Check source files
echo -e "\nChecking source files..."
[ -f "src/util/decoder.zig" ] && echo "✓ decoder.zig exists" || echo "✗ decoder.zig missing"
[ -f "src/util/runeset.zig" ] && echo "✓ runeset.zig exists" || echo "✗ runeset.zig missing"
[ -f "src/nf/nf.zig" ] && echo "✓ nf.zig exists" || echo "✗ nf.zig missing"
[ -f "src/ensip15/types.zig" ] && echo "✓ types.zig exists" || echo "✗ types.zig missing"
[ -f "src/ensip15/errors.zig" ] && echo "✓ errors.zig exists" || echo "✗ errors.zig missing"
[ -f "src/ensip15/ensip15.zig" ] && echo "✓ ensip15.zig exists" || echo "✗ ensip15.zig missing"
[ -f "src/ensip15/utils.zig" ] && echo "✓ utils.zig exists" || echo "✗ utils.zig missing"
[ -f "src/root.zig" ] && echo "✓ root.zig exists" || echo "✗ root.zig missing"

# Verify binary files
echo -e "\n=== Binary File Validation ==="
if [ -f "src/ensip15/spec.bin" ]; then
    SIZE=$(wc -c < "src/ensip15/spec.bin")
    echo "✓ spec.bin exists (${SIZE} bytes)"
    file src/ensip15/spec.bin
else
    echo "✗ spec.bin missing"
fi

if [ -f "src/nf/nf.bin" ]; then
    SIZE=$(wc -c < "src/nf/nf.bin")
    echo "✓ nf.bin exists (${SIZE} bytes)"
    file src/nf/nf.bin
else
    echo "✗ nf.bin missing"
fi

# Check test data
echo -e "\n=== Test Data Validation ==="
[ -d "test-data" ] && echo "✓ test-data/ directory exists" || echo "✗ test-data/ directory missing"
if [ -f "test-data/ensip15-tests.json" ]; then
    echo "✓ ensip15-tests.json exists"
    # Validate JSON
    python3 -m json.tool test-data/ensip15-tests.json > /dev/null 2>&1 && \
        echo "  ✓ Valid JSON" || echo "  ✗ Invalid JSON"
else
    echo "✗ ensip15-tests.json missing"
fi

if [ -f "test-data/nf-tests.json" ]; then
    echo "✓ nf-tests.json exists"
    # Validate JSON
    python3 -m json.tool test-data/nf-tests.json > /dev/null 2>&1 && \
        echo "  ✓ Valid JSON" || echo "  ✗ Invalid JSON"
else
    echo "✗ nf-tests.json missing"
fi

# Check test files
echo -e "\n=== Test File Validation ==="
[ -f "tests/json_parser.zig" ] && echo "✓ json_parser.zig exists" || echo "✗ json_parser.zig missing"
[ -f "tests/nf_test.zig" ] && echo "✓ nf_test.zig exists" || echo "✗ nf_test.zig missing"
[ -f "tests/ensip15_test.zig" ] && echo "✓ ensip15_test.zig exists" || echo "✗ ensip15_test.zig missing"

# Build verification
echo -e "\n=== Build System Validation ==="
echo "Running: zig build"
if zig build; then
    echo "✓ Build succeeded (exit code: $?)"
else
    echo "✗ Build failed (exit code: $?)"
    exit 1
fi

# Test verification
echo -e "\n=== Test Execution Validation ==="
echo "Running: zig build test"
echo "(Tests are expected to fail with unreachable/panic)"
zig build test 2>&1 | tee test-output.txt
TEST_EXIT=$?

# Analyze test output
echo -e "\n=== Test Output Analysis ==="
FAIL_COUNT=$(grep -c "FAIL" test-output.txt 2>/dev/null || echo "0")
PANIC_COUNT=$(grep -c "panic" test-output.txt 2>/dev/null || echo "0")
UNREACH_COUNT=$(grep -c "unreachable" test-output.txt 2>/dev/null || echo "0")

echo "Test failures: $FAIL_COUNT"
echo "Panics: $PANIC_COUNT"
echo "Unreachable: $UNREACH_COUNT"

if [ $FAIL_COUNT -gt 0 ] || [ $PANIC_COUNT -gt 0 ] || [ $UNREACH_COUNT -gt 0 ]; then
    echo "✓ Tests fail as expected (stubs not implemented)"
else
    echo "⚠ Warning: Tests should fail at this stage"
fi

# Build system features
echo -e "\n=== Build System Features ==="
echo "Available build steps:"
zig build --help | grep -A 20 "Steps:"

# Cleanup
rm -f test-output.txt

echo -e "\n=== Validation Complete ==="
```

## Expected Results

### Build Results
- **Status**: SUCCESS
- **Exit Code**: 0
- **Compile Errors**: 0
- **Warnings**: Acceptable (unused variables in stubs)
- **Output**: Clean build with no errors

### Test Results
- **Status**: FAIL (expected)
- **Exit Code**: Non-zero (expected)
- **Test Failures**: All tests fail
- **Failure Reason**: unreachable or panic in stubs
- **This is correct**: Tests should fail until implementation is complete

### Binary Files
- **spec.bin**: Present, non-empty, binary data file
- **nf.bin**: Present, non-empty, binary data file
- **File Type**: Data file (not text)
- **Size**: Matches source files in Go repository

### Test Data
- **ensip15-tests.json**: Valid JSON, contains test cases
- **nf-tests.json**: Valid JSON, contains test cases
- **Format**: Array of test objects
- **Accessibility**: Files readable by test code

### Prompts
- **Count**: 19 markdown files
- **Location**: prompts/ directory
- **Naming**: 01-18 plus this validation file
- **Content**: Complete task descriptions

## Success Criteria

The project passes validation when ALL of these criteria are met:

- [x] **All 19 prompts created**: Complete set of task descriptions
- [x] **All source files exist and compile**: No missing files, no compile errors
- [x] **All tests exist and run**: Test executable builds and executes
- [x] **Tests fail as expected**: All tests hit unreachable/panic (no implementation yet)
- [x] **No compile errors**: `zig build` exits with code 0
- [x] **Build system fully configured**: All build steps work correctly
- [x] **Binary data present**: spec.bin and nf.bin copied and accessible
- [x] **Test data present**: JSON files copied and valid
- [x] **Type system correct**: All types defined and consistent
- [x] **Documentation present**: Public API documented
- [x] **Ready for implementation**: Clear path forward to implement each module

## Next Steps: Implementation Phase

Once validation passes, proceed with implementation in this order:

### Phase 1: Foundation (Tasks 03-04)
1. **Implement StreamDecoder** (src/util/decoder.zig)
   - Implement `readByte()` for reading single bytes
   - Implement `readArray()` for variable-length arrays
   - Implement `readBranching()` for branching structures
   - Test with simple binary data

2. **Implement RuneSet** (src/util/runeset.zig)
   - Implement `contains()` for membership testing
   - Implement `fromArray()` for creating sets from arrays
   - Implement `fromRange()` for creating sets from ranges
   - Add helper methods as needed

### Phase 2: Normalization (Task 05)
3. **Implement NF normalization** (src/nf/nf.zig)
   - Load and parse nf.bin data
   - Implement NFD (canonical decomposition)
   - Implement NFC (canonical composition)
   - Verify with nf-tests.json

### Phase 3: ENSIP-15 Core (Tasks 08-09)
4. **Implement ENSIP-15 core logic** (src/ensip15/ensip15.zig)
   - Load and parse spec.bin data
   - Implement `split()` for label splitting
   - Implement `parseTokens()` for tokenization
   - Implement `processLabel()` for label validation
   - Implement `normalize()`, `beautify()`, `isNormalized()`

5. **Implement ENSIP-15 utilities** (src/ensip15/utils.zig)
   - Implement `isValidCodepoint()` for codepoint validation
   - Implement `getEmojiSequence()` for emoji handling
   - Add any additional helper functions

### Phase 4: Testing and Refinement
6. **Implement JSON parser** (tests/json_parser.zig)
   - Parse nf-tests.json
   - Parse ensip15-tests.json
   - Handle all test case formats

7. **Run and fix tests**
   - Run `zig build test` frequently
   - Fix failures one by one
   - Ensure all test cases pass
   - Add additional tests as needed

8. **Verify against Go implementation**
   - Compare output with Go implementation
   - Test edge cases
   - Verify performance
   - Ensure complete compatibility

### Expected Test Progression
- **Initially**: All tests fail with unreachable/panic
- **Phase 1**: Decoder and RuneSet tests pass
- **Phase 2**: NF normalization tests pass
- **Phase 3**: ENSIP-15 tests gradually pass
- **Phase 4**: All tests pass

## Common Issues and Troubleshooting

### Compile Errors

**Issue**: Type mismatch errors between modules
- **Cause**: Inconsistent type definitions
- **Solution**: Check that types are imported correctly and match declarations
- **Check**: Function signatures, error unions, return types

**Issue**: Cannot find imported module
- **Cause**: Incorrect import path or missing file
- **Solution**: Verify file exists and path is correct relative to project root
- **Check**: Use `@import("./filename.zig")` for same directory

**Issue**: Undefined symbol errors
- **Cause**: Function or type not exported
- **Solution**: Add `pub` keyword to declarations that need to be public
- **Check**: src/root.zig exports match what tests import

### Missing Files

**Issue**: Binary file not found
- **Cause**: File not copied from Go repository
- **Solution**: Run copy commands from Task 02 prompt
- **Check**: Verify file exists and has non-zero size

**Issue**: Test data not found
- **Cause**: test-data/ directory not created or files not copied
- **Solution**: Run `zig build copy-test-data` or copy manually
- **Check**: Verify JSON files are valid with `python3 -m json.tool`

**Issue**: Source file not found
- **Cause**: File not created or in wrong location
- **Solution**: Create file in correct directory following task prompts
- **Check**: Use `find . -name "*.zig"` to locate all Zig files

### Build System Errors

**Issue**: build.zig syntax errors
- **Cause**: Incorrect Zig build system API usage
- **Solution**: Check Zig version, verify syntax against Zig documentation
- **Check**: Ensure using correct API for your Zig version

**Issue**: Module not found in build
- **Cause**: Module not added to build.zig
- **Solution**: Add module with `b.addModule()` and reference in executable
- **Check**: Verify module paths are correct

**Issue**: Embedded file not found
- **Cause**: @embedFile path incorrect
- **Solution**: Use path relative to file containing @embedFile
- **Check**: Verify binary files exist at specified paths

### Test Failures

**Issue**: Tests fail immediately (expected at this stage)
- **Cause**: Stubs not implemented yet
- **Solution**: This is correct! Tests should fail until implementation
- **Check**: Verify failures are from unreachable/panic, not compile errors

**Issue**: Tests don't run at all
- **Cause**: Compilation error in test files
- **Solution**: Fix compile errors, ensure test file compiles
- **Check**: Run `zig build test` and read error messages carefully

**Issue**: Test executable crashes
- **Cause**: Null pointer, out of bounds access, or other runtime error
- **Solution**: Add bounds checking, validate inputs, use optional types
- **Check**: Run tests with `--summary all` for more details

### Binary File Issues

**Issue**: Binary file is empty or corrupted
- **Cause**: Incorrect copy command or transfer mode
- **Solution**: Re-copy files ensuring binary mode, verify checksums
- **Check**: Use `file` command to verify file type, check size matches source

**Issue**: Cannot read binary file
- **Cause**: File permissions or path issues
- **Solution**: Check file permissions with `ls -l`, verify path is correct
- **Check**: Use absolute paths, ensure file is readable

**Issue**: @embedFile fails
- **Cause**: File path incorrect or file not in project
- **Solution**: Verify path relative to source file, ensure file is in project tree
- **Check**: Path should be relative to the .zig file using @embedFile

## Checklist Summary Table

| # | Task | File(s) | Status |
|---|------|---------|--------|
| 01 | Project Setup | build.zig, src/root.zig | [ ] |
| 02 | Binary Data | spec.bin, nf.bin | [ ] |
| 03 | Decoder | src/util/decoder.zig | [ ] |
| 04 | RuneSet | src/util/runeset.zig | [ ] |
| 05 | NF Core | src/nf/nf.zig | [ ] |
| 06 | ENSIP15 Types | src/ensip15/types.zig | [ ] |
| 07 | ENSIP15 Errors | src/ensip15/errors.zig | [ ] |
| 08 | ENSIP15 Core | src/ensip15/ensip15.zig | [ ] |
| 09 | ENSIP15 Utils | src/ensip15/utils.zig | [ ] |
| 10 | Public API | src/root.zig (exports) | [ ] |
| 11 | JSON Parser | tests/json_parser.zig | [ ] |
| 12 | NF Tests | tests/nf_test.zig, test-data/nf-tests.json | [ ] |
| 13 | ENSIP15 Tests | tests/ensip15_test.zig, test-data/ensip15-tests.json | [ ] |
| 14 | Build System | build.zig (full config) | [ ] |
| 15 | Integration Tests | tests/*.zig (integration) | [ ] |
| 16 | Documentation | README.md, doc comments | [ ] |
| 17 | Examples | examples/*.zig | [ ] |
| 18 | CI Setup | .github/workflows/*.yml | [ ] |
| 19 | Validation | This checklist | [ ] |

## Final Validation Report Template

```
ENS Normalize Zig - Validation Report
=====================================

Date: _______________
Validator: _______________

File Structure: [ PASS / FAIL ]
  - Prompts: ___ / 19
  - Source files: ___ / 8
  - Binary files: ___ / 2
  - Test files: ___ / 3

Build System: [ PASS / FAIL ]
  - zig build: [ PASS / FAIL ]
  - zig build test: [ RUNS / FAILS TO RUN ]
  - zig build --help: [ PASS / FAIL ]

Code Quality: [ PASS / FAIL ]
  - Documentation: [ COMPLETE / INCOMPLETE ]
  - Stub quality: [ GOOD / NEEDS WORK ]
  - Type consistency: [ CONSISTENT / INCONSISTENT ]

Test Execution: [ PASS / FAIL ]
  - Tests compile: [ YES / NO ]
  - Tests run: [ YES / NO ]
  - Tests fail as expected: [ YES / NO ]

Overall Status: [ READY FOR IMPLEMENTATION / NEEDS WORK ]

Notes:
_______________________________________________
_______________________________________________
_______________________________________________

Next Action:
_______________________________________________
```

## Conclusion

This validation checklist ensures the complete skeleton codebase is ready for implementation. When all checks pass:

1. **Build system works**: Code compiles without errors
2. **Tests are in place**: All test cases defined and ready
3. **Structure is correct**: All files in proper locations
4. **Types are consistent**: No type mismatches between modules
5. **Documentation exists**: Public API is documented
6. **Path is clear**: Each module has a defined implementation task

The project is now ready to move from the scaffolding phase to the implementation phase, where each stub will be replaced with working code and tests will gradually turn from red to green.

**Remember**: At this validation stage, ALL TESTS SHOULD FAIL. This is correct and expected. Tests failing with unreachable/panic indicates the stubs are properly in place and ready to be implemented.
