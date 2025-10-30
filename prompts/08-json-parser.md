# Task 08: Create JSON Test Data Parser

## Goal

Write Zig code to parse the test JSON files and return structured test case data in `tests/json_parser.zig`. This parser will enable the Zig test suite to consume the same JSON test data files used by the Go implementation, ensuring test parity across implementations.

## Context

The Go implementation uses two JSON test files with different structures:
1. **ENSIP15 tests** (`tests.json`): Array of test objects for normalization
2. **NF tests** (`nf-tests.json`): Map of test names to arrays of [input, NFD, NFC] tuples

This task creates a Zig module to parse both formats into strongly-typed structs that can be used by the test suite.

## Go Reference Code

### ENSIP15 Test Parser

From `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/ensip15_test.go`:

```go
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
        // Note: If norm is empty, it defaults to name
        if len(test.Norm) == 0 {
            test.Norm = test.Name
        }
        // ... run test ...
    }
}
```

### NF Test Parser

From `/Users/williamcory/z-ens-normalize/go-ens-normalize/nf/nf_test.go`:

```go
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
                input := []rune(v[0].(string))  // Input string
                nfd0 := []rune(v[1].(string))   // Expected NFD
                nfc0 := []rune(v[2].(string))   // Expected NFC
                // ... run test ...
            }
        })
    }
}
```

## Test JSON Structures

### ENSIP15 Format (`tests.json`)

```json
[
  {
    "name": "input string",
    "norm": "expected normalized string",
    "error": false,
    "comment": "descriptive comment"
  },
  {
    "name": "invalid input",
    "norm": "",
    "error": true,
    "comment": "should fail"
  }
]
```

**Key points:**
- Array of test case objects
- `name`: Input string to normalize
- `norm`: Expected normalized output (may be empty, defaults to `name` if not provided)
- `error`: Boolean indicating if normalization should fail
- `comment`: Human-readable description

### NF Format (`nf-tests.json`)

```json
{
  "testName1": [
    ["input1", "expectedNFD1", "expectedNFC1"],
    ["input2", "expectedNFD2", "expectedNFC2"]
  ],
  "testName2": [
    ["input3", "expectedNFD3", "expectedNFC3"]
  ]
}
```

**Key points:**
- Object/map with test names as keys
- Each value is an array of test cases
- Each test case is a 3-element array: [input, expected NFD, expected NFC]

## Implementation Guidance

### File Structure

Create `tests/json_parser.zig` with the following components:

1. **Imports**
   ```zig
   const std = @import("std");
   const testing = std.testing;
   ```

2. **ENSIP15 Test Case Struct**
   ```zig
   pub const Ensip15TestCase = struct {
       name: []const u8,
       norm: []const u8,
       error: bool,
       comment: []const u8,
   };
   ```

3. **NF Test Case Struct**
   ```zig
   pub const NfTestCase = struct {
       input: []const u8,
       nfd: []const u8,
       nfc: []const u8,
   };

   pub const NfTestGroup = struct {
       name: []const u8,
       cases: []NfTestCase,
   };
   ```

4. **Parser Functions**
   ```zig
   /// Parse ENSIP15 test JSON file
   /// Returns array of test cases
   /// Caller owns the returned memory
   pub fn parseEnsip15Tests(
       allocator: std.mem.Allocator,
       json_data: []const u8,
   ) ![]Ensip15TestCase {
       // For now, return empty array (stub implementation)
       _ = json_data;
       return allocator.alloc(Ensip15TestCase, 0);
   }

   /// Parse NF test JSON file
   /// Returns array of test groups
   /// Caller owns the returned memory
   pub fn parseNfTests(
       allocator: std.mem.Allocator,
       json_data: []const u8,
   ) ![]NfTestGroup {
       // For now, return empty array (stub implementation)
       _ = json_data;
       return allocator.alloc(NfTestGroup, 0);
   }
   ```

### Using std.json.parseFromSlice

When implementing the actual parser (future task), use Zig's JSON parser:

```zig
const parsed = try std.json.parseFromSlice(
    []Ensip15TestCase,
    allocator,
    json_data,
    .{},
);
defer parsed.deinit();

// Copy data for return
const tests = try allocator.alloc(Ensip15TestCase, parsed.value.len);
for (parsed.value, 0..) |test_case, i| {
    tests[i] = test_case;
}
return tests;
```

### Important Notes

- **Memory Management**: Parser functions accept an allocator and return allocated memory. Caller is responsible for freeing.
- **Optional Fields**: The `norm` field in ENSIP15 tests can be empty and should default to `name` value.
- **Error Handling**: Use Zig's error unions (`!`) for all fallible operations.
- **Stub Implementation**: For this task, return empty arrays. Full parsing will be implemented in a later task.

## File Location

```
tests/json_parser.zig
```

## Dependencies

### Required Tasks
- **Task 05**: Test data files must exist at proper locations
  - `go-ens-normalize/ensip15/tests.json`
  - `go-ens-normalize/nf/nf-tests.json`

### Zig Standard Library
- `std.json` for JSON parsing
- `std.mem.Allocator` for memory allocation
- `std.testing` for test utilities

## Success Criteria

- [ ] File `tests/json_parser.zig` exists
- [ ] `Ensip15TestCase` struct defined with correct fields
- [ ] `NfTestCase` and `NfTestGroup` structs defined with correct fields
- [ ] `parseEnsip15Tests()` function defined (stub implementation returning empty array)
- [ ] `parseNfTests()` function defined (stub implementation returning empty array)
- [ ] Both parser functions accept allocator parameter
- [ ] Both parser functions return error unions with proper types
- [ ] File compiles without errors
- [ ] No warnings from `zig build`

## Validation Commands

### Compile Check
```bash
cd /Users/williamcory/z-ens-normalize
zig build
```

### Expected Output
```
Build Completed Successfully
```

No errors or warnings should be present.

### Additional Validation
```bash
# Verify file exists
ls -l tests/json_parser.zig

# Check file compiles independently
zig test tests/json_parser.zig
```

## Common Pitfalls

### 1. JSON Parsing Requires Allocator
```zig
// WRONG: No allocator provided
const parsed = try std.json.parseFromSlice([]TestCase, json_data, .{});

// CORRECT: Allocator is first parameter after type
const parsed = try std.json.parseFromSlice([]TestCase, allocator, json_data, .{});
```

### 2. Handling Optional/Empty Fields
```zig
// In ENSIP15 tests, norm can be empty
// Handle this in your parser:
if (test_case.norm.len == 0) {
    test_case.norm = test_case.name;
}
```

### 3. Memory Ownership
```zig
// Parsed data must be deferred for cleanup
const parsed = try std.json.parseFromSlice(...);
defer parsed.deinit(); // Don't forget this!

// Then copy data if you need to return it
const result = try allocator.dupe(TestCase, parsed.value);
return result;
```

### 4. Using Testing Allocator
```zig
// In tests, always use testing.allocator
test "parse ensip15 tests" {
    const allocator = testing.allocator;
    const tests = try parseEnsip15Tests(allocator, json_data);
    defer allocator.free(tests);
    // ... assertions ...
}
```

### 5. Nested Structures in NF Tests
```zig
// NF tests have nested structure: map -> array -> array
// You'll need to:
// 1. Parse as std.json.Value to handle dynamic structure
// 2. Iterate over object keys
// 3. Parse arrays within arrays
// Example structure:
const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_data, .{});
defer parsed.deinit();

const obj = parsed.value.object;
for (obj.keys()) |key| {
    const test_array = obj.get(key).?.array;
    for (test_array.items) |item| {
        const tuple = item.array;
        const input = tuple.items[0].string;
        const nfd = tuple.items[1].string;
        const nfc = tuple.items[2].string;
        // ... process test case ...
    }
}
```

### 6. Stub Implementation
```zig
// For this task, stub implementations are acceptable:
pub fn parseEnsip15Tests(
    allocator: std.mem.Allocator,
    json_data: []const u8,
) ![]Ensip15TestCase {
    _ = json_data; // Suppress unused parameter warning
    return allocator.alloc(Ensip15TestCase, 0); // Return empty array
}
```

## Testing Strategy

### Basic Compilation Test
```zig
test "json_parser compiles" {
    // This test just ensures the file compiles
    const allocator = testing.allocator;

    const ensip15_tests = try parseEnsip15Tests(allocator, "[]");
    defer allocator.free(ensip15_tests);
    try testing.expectEqual(@as(usize, 0), ensip15_tests.len);

    const nf_tests = try parseNfTests(allocator, "{}");
    defer allocator.free(nf_tests);
    try testing.expectEqual(@as(usize, 0), nf_tests.len);
}
```

### Future Tests (Next Task)
Once full parsing is implemented:
- Parse valid ENSIP15 JSON and verify struct fields
- Parse valid NF JSON and verify nested structure
- Handle empty norm field defaulting to name
- Handle malformed JSON gracefully
- Test memory cleanup with testing.allocator

## Next Steps

After completing this task:
1. **Task 09**: Implement full JSON parsing logic (replace stubs)
2. **Task 10**: Create test runner that uses parsed data
3. **Task 11**: Implement actual normalization and compare against expected values

## Related Files

- `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/ensip15_test.go` - Go ENSIP15 test reference
- `/Users/williamcory/z-ens-normalize/go-ens-normalize/nf/nf_test.go` - Go NF test reference
- `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/tests.json` - ENSIP15 test data
- `/Users/williamcory/z-ens-normalize/go-ens-normalize/nf/nf-tests.json` - NF test data

## Reference Documentation

- [Zig std.json Documentation](https://ziglang.org/documentation/master/std/#A;std:json)
- [Zig Memory Allocators](https://ziglang.org/documentation/master/std/#A;std:mem)
- [Go encoding/json Package](https://pkg.go.dev/encoding/json) - For comparison
