# Task 17: Implement NF Test Suite

## Goal

Port the NF test suite from Go to Zig as `tests/nf_test.zig`. This test suite reads `nf-tests.json` and validates NFC (Normalization Form Composed) and NFD (Normalization Form Decomposed) normalization against expected outputs.

## Go Reference Code

The Go implementation from `/Users/williamcory/z-ens-normalize/go-ens-normalize/nf/nf_test.go`:

```go
package nf

import (
	"encoding/json"
	"io"
	"os"
	"testing"
)

func readJSONFile(path string) []byte {
	file, err := os.Open(path)
	if err != nil {
		panic(err)
	}
	defer file.Close()
	v, err := io.ReadAll(file)
	if err != nil {
		panic(err)
	}
	return v
}

func TestNF(t *testing.T) {
	nf := New()
	var tests map[string]interface{}
	err := json.Unmarshal(readJSONFile("nf-tests.json"), &tests)
	if err != nil {
		panic(err)
	}
	for name, value := range tests {
		list, ok := value.([]interface{})
		if !ok {
			continue
		}
		t.Run(name, func(t *testing.T) {
			for i, x := range list {
				v := x.([]interface{})
				input := []rune(v[0].(string))
				nfd0 := []rune(v[1].(string))
				nfc0 := []rune(v[2].(string))
				nfd := nf.NFD(input)
				nfc := nf.NFC(input)
				if string(nfd) != string(nfd0) {
					t.Errorf("NFD[%d]: expect %v, got %v", i, nfd0, nfd)
				}
				if string(nfc) != string(nfc0) {
					t.Errorf("NFC[%d]: expect %v, got %v", i, nfc0, nfc)
				}
			}
		})
	}
}
```

## Test JSON Structure

The `nf-tests.json` file has the following structure:

```json
{
  "Specific cases": [
    ["input_string", "expected_nfd", "expected_nfc"],
    ["Ḋ", "Ḋ", "Ḋ"],
    ...
  ],
  "Character by character test": [
    [" ", " ", " "],
    ["café", "café", "café"],
    ...
  ]
}
```

### Format Details:
- **Top-level map**: Keys are test category names (strings), values are arrays of test cases
- **Test case array**: Each test case is a 3-element array:
  - `[0]`: Input string to normalize
  - `[1]`: Expected NFD (Normalization Form Decomposed) output
  - `[2]`: Expected NFC (Normalization Form Composed) output
- **Categories**: The JSON contains multiple test categories like:
  - "Specific cases" - edge cases and specific Unicode normalization scenarios
  - "Character by character test" - comprehensive character-by-character validation

### Example Test Cases:
```json
{
  "Latin": [
    ["café", "café", "café"],
    ["È", "È", "È"]
  ]
}
```

## Implementation Guidance

### 1. Use `std.testing` Framework
```zig
const std = @import("std");
const testing = std.testing;
```

### 2. Read and Parse JSON
- Use the `json_parser.zig` utility from Task 08 to read `test-data/nf-tests.json`
- Alternatively, use `@embedFile` to embed the JSON at compile time:
  ```zig
  const json_data = @embedFile("../test-data/nf-tests.json");
  ```

### 3. Test Structure
```zig
test "NF normalization tests" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize NF
    const nf = try NF.init(allocator);
    defer nf.deinit();

    // Parse JSON test data
    const json_data = @embedFile("../test-data/nf-tests.json");
    // Parse using std.json or json_parser from Task 08

    // For each test category...
    // For each test case...
}
```

### 4. Iterate Through Test Cases
For each test category and test case:
1. Extract input, expected NFD, and expected NFC from the 3-element array
2. Convert UTF-8 string (`[]const u8`) to codepoints (`[]const u21`) using `Decoder` from Task 01
3. Call `nf.nfd()` and `nf.nfc()` methods
4. Convert results back to UTF-8 for comparison
5. Compare with expected values using `std.testing.expectEqualStrings`

### 5. Memory Management
```zig
// Call normalization methods
const nfd_result = try nf.nfd(allocator, input_codepoints);
defer allocator.free(nfd_result);

const nfc_result = try nf.nfc(allocator, input_codepoints);
defer allocator.free(nfc_result);

// Use std.testing.allocator to detect memory leaks
```

### 6. String Comparison
```zig
// Convert codepoints back to UTF-8 for comparison
const nfd_utf8 = try codepointsToUtf8(allocator, nfd_result);
defer allocator.free(nfd_utf8);

try testing.expectEqualStrings(expected_nfd, nfd_utf8);
```

### 7. Error Messages
Include helpful error messages with:
- Test category name
- Test case index
- Input value (preferably as hex codepoints)
- Expected vs actual output

Example:
```zig
std.debug.print("NFD test failed in '{s}' at index {d}\n", .{category_name, index});
std.debug.print("  Input: {s} (U+{X}...)\n", .{input, input[0]});
std.debug.print("  Expected: {s}\n", .{expected_nfd});
std.debug.print("  Got: {s}\n", .{nfd_utf8});
```

## File Location

Create: `/Users/williamcory/z-ens-normalize/tests/nf_test.zig`

## Dependencies

This task depends on:

1. **Task 05**: `test-data/nf-tests.json` must exist
2. **Task 08**: `json_parser.zig` implemented for JSON parsing
3. **Task 01**: `Decoder` utility for UTF-8 to codepoint conversion
4. **Task 09**: `NF.init()` method defined
5. **Task 10**: `NF.nfd()` and `NF.nfc()` methods defined (even if stubbed)

## Success Criteria

- [ ] File `tests/nf_test.zig` exists
- [ ] Test reads `nf-tests.json` from `test-data/` directory
- [ ] JSON is successfully parsed using `json_parser` or `std.json`
- [ ] Creates `NF` instance with `init()`
- [ ] For each test case:
  - [ ] Calls `nfd()` with input codepoints
  - [ ] Calls `nfc()` with input codepoints
  - [ ] Compares results with expected values
- [ ] Uses `std.testing.allocator` for automatic leak detection
- [ ] File compiles without errors: `zig build test`
- [ ] Tests run (they will FAIL until NF is fully implemented - this is expected)
- [ ] Test output clearly shows which tests fail and why

## Validation Commands

```bash
# Compile and run tests
zig build test 2>&1 | head -50

# Expected output: Tests compile and run, but fail with unreachable/panic/TODO messages
# This is EXPECTED - NF implementation is stubbed in Task 10
```

### Expected Behavior

The tests should:
1. **Compile successfully** - No syntax or type errors
2. **Run** - Test framework executes the test
3. **FAIL** - Because `nfd()` and `nfc()` are stubbed (return unreachable or panic)
4. **Show clear failure messages** - Indicate which test category and case failed

Example expected output:
```
Test [1/1] test.NF normalization tests...
thread 123456 panic: TODO: implement NFD
/Users/williamcory/z-ens-normalize/src/nf.zig:45:5
Test [1/1] test.NF normalization tests... FAIL (Panicked)
```

## Common Pitfalls

### 1. JSON File Path
- Must be relative to the test file location
- Use `@embedFile("../test-data/nf-tests.json")` for compile-time embedding
- Or use runtime file reading with correct relative path

### 2. Memory Management
```zig
// WRONG - memory leak
const result = try nf.nfd(allocator, input);
try testing.expectEqualStrings(expected, result);

// CORRECT - free allocated memory
const result = try nf.nfd(allocator, input);
defer allocator.free(result);
try testing.expectEqualStrings(expected, result);
```

### 3. UTF-8 vs Codepoints
```zig
// Input from JSON is UTF-8 ([]const u8)
const input_utf8: []const u8 = "café";

// NF methods expect codepoints ([]const u21)
const input_codepoints = try utf8ToCodepoints(allocator, input_utf8);
defer allocator.free(input_codepoints);

// Call NF methods with codepoints
const result = try nf.nfd(allocator, input_codepoints);
```

### 4. Test Allocator Leak Detection
```zig
// Use GeneralPurposeAllocator or testing.allocator
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer {
    const leaked = gpa.deinit();
    if (leaked) {
        std.debug.print("Memory leak detected!\n", .{});
    }
}
```

### 5. Expected Test Failures
```zig
// Tests WILL fail - this is expected
// NF.nfd() and NF.nfc() are stubbed in Task 10
// They return `unreachable` or `@panic("TODO")`
//
// DO NOT try to make tests pass by:
// - Returning input unchanged
// - Commenting out assertions
// - Skipping test cases
//
// The goal is to have a WORKING test framework
// that fails with clear messages
```

### 6. JSON Parsing Edge Cases
- Handle empty test categories (skip them)
- Handle malformed test arrays (not exactly 3 elements)
- Handle non-string values gracefully
- Report JSON parsing errors clearly

### 7. Unicode Display in Error Messages
```zig
// Include both string and hex codepoints for debugging
std.debug.print("Input: '{s}' ", .{input_utf8});
std.debug.print("[", .{});
for (input_codepoints, 0..) |cp, i| {
    if (i > 0) std.debug.print(" ", .{});
    std.debug.print("U+{X:0>4}", .{cp});
}
std.debug.print("]\n", .{});
```

## Test Structure Options

### Option A: Single umbrella test
```zig
test "NF normalization tests" {
    // Load all test data
    // Iterate all categories
    // Run all test cases
    // Report all failures
}
```

### Option B: One test per category
```zig
test "NF: Specific cases" {
    // Test only "Specific cases" category
}

test "NF: Character by character test" {
    // Test only "Character by character test" category
}
```

**Recommendation**: Use Option A (single umbrella test) initially for simplicity. Option B can be implemented later for better failure isolation.

## Example Test Skeleton

```zig
const std = @import("std");
const testing = std.testing;
const NF = @import("../src/nf.zig").NF;
const Decoder = @import("../src/util/decoder.zig").Decoder;

test "NF normalization tests" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize NF
    const nf = try NF.init(allocator);
    defer nf.deinit();

    // Read test data
    const json_data = @embedFile("../test-data/nf-tests.json");

    // Parse JSON (using std.json or json_parser)
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_data,
        .{}
    );
    defer parsed.deinit();

    const root = parsed.value.object;

    // Iterate through each test category
    var it = root.iterator();
    while (it.next()) |entry| {
        const category_name = entry.key_ptr.*;
        const test_cases = entry.value_ptr.*.array;

        std.debug.print("\nTesting category: {s}\n", .{category_name});

        // Iterate through each test case in the category
        for (test_cases.items, 0..) |test_case, i| {
            const case_array = test_case.array;

            // Extract input, expected NFD, expected NFC
            const input_utf8 = case_array.items[0].string;
            const expected_nfd = case_array.items[1].string;
            const expected_nfc = case_array.items[2].string;

            // Convert to codepoints
            const input_cps = try utf8ToCodepoints(allocator, input_utf8);
            defer allocator.free(input_cps);

            // Test NFD
            const nfd_result = try nf.nfd(allocator, input_cps);
            defer allocator.free(nfd_result);

            const nfd_utf8 = try codepointsToUtf8(allocator, nfd_result);
            defer allocator.free(nfd_utf8);

            testing.expectEqualStrings(expected_nfd, nfd_utf8) catch |err| {
                std.debug.print("NFD FAIL [{s}][{d}]: {s}\n", .{
                    category_name, i, input_utf8
                });
                return err;
            };

            // Test NFC
            const nfc_result = try nf.nfc(allocator, input_cps);
            defer allocator.free(nfc_result);

            const nfc_utf8 = try codepointsToUtf8(allocator, nfc_result);
            defer allocator.free(nfc_utf8);

            testing.expectEqualStrings(expected_nfc, nfc_utf8) catch |err| {
                std.debug.print("NFC FAIL [{s}][{d}]: {s}\n", .{
                    category_name, i, input_utf8
                });
                return err;
            };
        }
    }
}

// Helper function to convert UTF-8 to codepoints
fn utf8ToCodepoints(allocator: std.mem.Allocator, utf8: []const u8) ![]u21 {
    var decoder = Decoder.init(utf8);
    var codepoints = std.ArrayList(u21).init(allocator);
    defer codepoints.deinit();

    while (try decoder.next()) |cp| {
        try codepoints.append(cp);
    }

    return codepoints.toOwnedSlice();
}

// Helper function to convert codepoints to UTF-8
fn codepointsToUtf8(allocator: std.mem.Allocator, cps: []const u21) ![]u8 {
    var utf8 = std.ArrayList(u8).init(allocator);
    defer utf8.deinit();

    for (cps) |cp| {
        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(cp, &buf);
        try utf8.appendSlice(buf[0..len]);
    }

    return utf8.toOwnedSlice();
}
```

## Notes

1. **Tests WILL fail** - This is expected and correct. The NF implementation is stubbed in Task 10.
2. **Clear failure messages** - Make sure test failures clearly indicate which category and test case failed.
3. **Memory safety** - Use testing allocator to ensure no memory leaks in the test code itself.
4. **Incremental development** - Start with parsing the JSON and printing test cases before implementing full assertions.
5. **Debugging aid** - Consider adding a flag to print all test cases before running them to verify JSON parsing.

## Future Work

After implementing NF normalization (Task 18+), these tests will:
1. Start passing gradually as NF implementation is completed
2. Provide regression testing for the normalization logic
3. Ensure compatibility with the Go reference implementation
4. Validate edge cases and special Unicode characters

The test suite is a critical validation tool - even though it fails initially, having it in place early ensures the implementation can be tested incrementally.
