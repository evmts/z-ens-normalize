# Task 18: Implement ENSIP15 Test Suite

## Goal

Port the ENSIP15 test suite from Go to Zig as `tests/ensip15_test.zig`. This validates the complete ENS normalization pipeline by running all official ENSIP-15 test cases against your implementation.

The tests will initially **FAIL** (this is expected) because the normalization logic is stubbed. As you implement Tasks 19-23 (the actual normalization algorithms), these tests will progressively pass.

## Go Reference Code

```go
package ensip15

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

func TestNormalize(t *testing.T) {
	l := New()
	type Test struct {
		Name    string `json:"name"`
		Norm    string `json:"norm"`
		Error   bool   `json:"error"`
		Comment string `json:"comment"`
	}
	var tests []Test
	err := json.Unmarshal(readJSONFile("tests.json"), &tests)
	if err != nil {
		panic(err)
	}
	for _, test := range tests {
		if len(test.Norm) == 0 {
			test.Norm = test.Name
		}
		t.Run(ToHexSequence([]rune(test.Name)), func(t *testing.T) {
			norm, err := l.Normalize(test.Name)
			if test.Error {
				if err == nil {
					t.Errorf("expected error: %s", ToHexSequence([]rune(norm)))
				}
			} else if err != nil {
				t.Errorf("unexpected error: %v", err)
			} else if norm != test.Norm {
				t.Errorf("wrong norm: %s vs %s", ToHexSequence([]rune(test.Norm)), ToHexSequence([]rune(norm)))
			}
		})
	}
}
```

## Test JSON Structure

The `test-data/ensip15-tests.json` file contains an array of test cases. Each test object has:

```json
{
  "name": "input",      // The input string to normalize
  "norm": "expected",   // Expected normalized output (empty = idempotent)
  "error": false,       // true if normalization should fail
  "comment": "..."      // Description of what this test validates
}
```

**Important behaviors:**
- **First element is metadata**: Skip the first entry (contains version info)
- **Empty "norm" field**: If `norm` is empty string, the expected output equals `name` (idempotent test)
- **Error flag**: If `error` is true, the normalize() call should return an error
- **Success validation**: If `error` is false, verify that normalize() returns the expected `norm` value

Example test cases:
```json
[
  {"name": "1.0.0", "norm": "", "error": false, "comment": "version metadata - SKIP"},
  {"name": "nick.eth", "norm": "", "error": false, "comment": "valid, already normalized"},
  {"name": "Nick.ETH", "norm": "nick.eth", "error": false, "comment": "uppercase to lowercase"},
  {"name": "a\u200db", "norm": "", "error": true, "comment": "zero-width joiner invalid"}
]
```

## Implementation Guidance

### Overall Structure

Create a comprehensive test that:
1. Reads `test-data/ensip15-tests.json` file
2. Parses JSON using the json_parser from Task 08
3. Skips the first entry (version metadata)
4. Creates an ENSIP15 instance with `init()`
5. Iterates through each test case
6. Calls `normalize()` on the input
7. Validates the result matches expectations

### Key Implementation Points

**File I/O:**
```zig
const test_data = @embedFile("../test-data/ensip15-tests.json");
```

**JSON Parsing:**
```zig
const json_parser = @import("../src/json_parser.zig");
var parsed = try json_parser.parse(std.testing.allocator, test_data);
defer parsed.deinit();
```

**Test Structure:**
```zig
const TestCase = struct {
    name: []const u8,
    norm: []const u8,
    error: bool,
    comment: []const u8,
};
```

**Main Test Loop:**
```zig
test "ENSIP15 normalization test suite" {
    const allocator = std.testing.allocator;

    // Parse JSON test cases
    // Skip first entry (version metadata)
    // Create ENSIP15 instance

    var ensip15 = try ENSIP15.init(allocator);
    defer ensip15.deinit();

    for (tests[1..]) |test_case| {
        // Determine expected output (handle empty norm field)
        const expected = if (test_case.norm.len == 0)
            test_case.name
        else
            test_case.norm;

        // Call normalize
        const result = ensip15.normalize(allocator, test_case.name);

        if (test_case.error) {
            // Should fail
            try std.testing.expectError(error.*, result);
        } else {
            // Should succeed
            const normalized = try result;
            defer allocator.free(normalized);

            try std.testing.expectEqualStrings(expected, normalized);
        }
    }
}
```

**Memory Management:**
- Use `std.testing.allocator` - it will detect leaks
- Free normalized strings after validation
- Parser cleanup with `defer parsed.deinit()`
- ENSIP15 cleanup with `defer ensip15.deinit()`

**Test Names & Debugging:**
- Use the `comment` field for test identification
- Consider printing hex codepoints for failures (like Go's ToHexSequence)
- Group tests by category if desired (ASCII, emoji, confusables, etc.)

**Handling Long Inputs:**
- Some test cases have very long input strings
- Ensure your buffer allocations can handle them
- Consider truncating debug output for readability

## File Location

Create: `/Users/williamcory/z-ens-normalize/tests/ensip15_test.zig`

## Dependencies

This task requires:

- **Task 05**: `test-data/ensip15-tests.json` exists
- **Task 08**: `json_parser.zig` implemented
- **Task 11**: `ENSIP15.init()` defined in `src/ensip15.zig`
- **Task 13**: `ENSIP15.normalize()` defined (currently stubbed)

## Success Criteria

- [ ] File `tests/ensip15_test.zig` exists
- [ ] Test reads `ensip15-tests.json` using `@embedFile`
- [ ] Parses JSON using json_parser module
- [ ] Skips version metadata (first array entry)
- [ ] Creates ENSIP15 instance with `init()`
- [ ] For each test case: calls `normalize()`
- [ ] Handles both success and error cases correctly
- [ ] Handles empty norm field (idempotent check)
- [ ] Compares results with expected values using `std.testing.expectEqualStrings`
- [ ] Uses `std.testing.allocator` for all allocations
- [ ] File compiles without errors
- [ ] `zig build test` runs tests (they will FAIL - this is expected)
- [ ] Test output shows meaningful failure messages with context

## Validation Commands

Run the test suite:
```bash
zig build test
```

Check ENSIP15 test output specifically:
```bash
zig build test 2>&1 | grep -A5 "ensip15"
```

Expected output (tests will fail):
```
Test [1/1] tests.ensip15_test... FAIL (UnexpectedError)
  thread 123456 panic: attempt to use stub function
  ...
```

This is **normal and expected**. The tests will fail until you implement the normalization algorithms in Tasks 19-23.

## Common Pitfalls

1. **Metadata Entry**: The first JSON array element is version metadata, not a test case. Always skip it with `tests[1..]`.

2. **Empty Norm Field**: When `norm` is empty string, the test expects the output to equal the input (idempotent). Don't skip these tests!

3. **Error Expectations**: Some tests expect errors. Use `std.testing.expectError()` for these cases, not `expectEqualStrings()`.

4. **Memory Leaks**: The test allocator will fail if you forget to free normalized strings. Always `defer allocator.free(normalized)`.

5. **Test Names**: Make test failure messages descriptive. Include the comment field or hex codepoints to identify which test failed.

6. **Long Test Cases**: Some tests have inputs with hundreds of characters. Don't panic on long strings; handle them gracefully.

7. **Stub Panics**: The current `normalize()` implementation is stubbed and will panic. This is expected - don't try to "fix" the tests to avoid this.

8. **UTF-8 Encoding**: Ensure proper handling of multi-byte UTF-8 sequences when comparing strings.

9. **Case Sensitivity**: String comparison should be exact after normalization. Use `expectEqualStrings`, not case-insensitive comparison.

10. **Allocation Failures**: Handle potential allocation failures with `try` - don't unwrap with `.?` in tests.

## Test Organization Options

You can organize the tests in different ways:

### Option 1: Single Large Test
One test that iterates all cases (like the Go version):
```zig
test "ENSIP15 complete test suite" {
    // Load all tests
    // Run them all in a loop
}
```

**Pros**: Simple, matches Go structure
**Cons**: Hard to identify which specific test failed

### Option 2: Separate Error/Success Tests
```zig
test "ENSIP15 success cases" {
    // Only run tests where error == false
}

test "ENSIP15 error cases" {
    // Only run tests where error == true
}
```

**Pros**: Clear separation of concerns
**Cons**: Still many tests per category

### Option 3: Category Groups
```zig
test "ENSIP15 ASCII tests" { }
test "ENSIP15 emoji tests" { }
test "ENSIP15 confusable tests" { }
test "ENSIP15 disallowed tests" { }
```

**Pros**: Fine-grained failure identification
**Cons**: Requires categorizing tests (use comment field)

**Recommendation**: Start with Option 1 (single test) to match the Go reference. You can refactor later if needed.

## Expected Test Progression

As you complete later tasks, tests will progressively pass:

- **Now (Task 18)**: All tests fail with "stub function" panic
- **After Task 19-20**: Some basic ASCII tests pass
- **After Task 21**: Emoji and combining mark tests pass
- **After Task 22**: Confusable detection tests pass
- **After Task 23**: All tests should pass

## Additional Notes

- The test file should be runnable with `zig build test` even though tests fail
- Consider adding a helper function to print failing test info
- You may want to collect failures and print a summary at the end
- The Go version uses `ToHexSequence()` for debug output - consider porting this utility
- Some test comments reference ENSIP-15 spec sections - these are educational

## Example Test Output Format

When a test fails, provide useful context:
```
Test case: "Nick.ETH" (uppercase to lowercase)
  Expected: "nick.eth"
  Got: "Nick.ETH"
  Codepoints: [4E 69 63 6B 2E 45 54 48]
```

This helps debug normalization issues quickly.

## Next Steps

After implementing this task:
1. Verify tests compile and run (even though they fail)
2. Proceed to Task 19: Implement NF decomposition
3. Watch tests progressively pass as you implement normalization logic
4. Use failing tests to guide your implementation priorities
