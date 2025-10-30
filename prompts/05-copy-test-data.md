# Task 05: Set Up Test Data Acquisition

## Goal

Create a Zig build step that copies test JSON files from the Go reference implementation to our test-data directory. This ensures we have the canonical test data available for validating our ENS normalization implementation.

## Background

The Go ENS normalize implementation (`go-ens-normalize`) contains comprehensive test data in JSON format:
- **ensip15/tests.json**: Contains test cases for the full ENSIP-15 normalization specification
- **nf/nf-tests.json**: Contains Unicode normalization form test cases

We need to copy these files to a dedicated `test-data/` directory in our Zig project for use in our test suite.

## Implementation Guidance

### Approach 1: Build.zig Step (Recommended)

Add a build step in `build.zig` that copies the test data files:

```zig
// Add a step to copy test data
const copy_test_data = b.step("copy-test-data", "Copy test data from go-ens-normalize");

// Create test-data directory
const test_data_dir = "test-data";
const mkdir_step = b.addSystemCommand(&.{"mkdir", "-p", test_data_dir});
copy_test_data.dependOn(&mkdir_step.step);

// Copy ensip15 tests
const copy_ensip15 = b.addSystemCommand(&.{
    "cp",
    "go-ens-normalize/ensip15/tests.json",
    "test-data/ensip15-tests.json"
});
copy_ensip15.step.dependOn(&mkdir_step.step);
copy_test_data.dependOn(&copy_ensip15.step);

// Copy nf tests
const copy_nf = b.addSystemCommand(&.{
    "cp",
    "go-ens-normalize/nf/nf-tests.json",
    "test-data/nf-tests.json"
});
copy_nf.step.dependOn(&mkdir_step.step);
copy_test_data.dependOn(&copy_nf.step);
```

### Approach 2: Standalone Script (Alternative)

Create a simple utility script at `tools/copy_test_data.zig`:

```zig
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create test-data directory
    std.fs.cwd().makeDir("test-data") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Copy files
    const files = [_]struct { src: []const u8, dst: []const u8 }{
        .{ .src = "go-ens-normalize/ensip15/tests.json", .dst = "test-data/ensip15-tests.json" },
        .{ .src = "go-ens-normalize/nf/nf-tests.json", .dst = "test-data/nf-tests.json" },
    };

    for (files) |file| {
        std.fs.cwd().copyFile(file.src, std.fs.cwd(), file.dst, .{}) catch |err| {
            std.debug.print("Error copying {s}: {}\n", .{ file.src, err });
            return err;
        };
        std.debug.print("Copied {s} -> {s}\n", .{ file.src, file.dst });
    }

    std.debug.print("Test data copied successfully!\n", .{});
}
```

Then add to `build.zig`:

```zig
const copy_tool = b.addExecutable(.{
    .name = "copy_test_data",
    .root_source_file = .{ .path = "tools/copy_test_data.zig" },
    .target = target,
    .optimize = optimize,
});

const copy_test_data = b.step("copy-test-data", "Copy test data from go-ens-normalize");
const run_copy = b.addRunArtifact(copy_tool);
copy_test_data.dependOn(&run_copy.step);
```

## Files to Copy

| Source File | Destination File | Purpose |
|-------------|------------------|---------|
| `go-ens-normalize/ensip15/tests.json` | `test-data/ensip15-tests.json` | ENSIP-15 normalization tests |
| `go-ens-normalize/nf/nf-tests.json` | `test-data/nf-tests.json` | Unicode normalization tests |

## JSON Structure Examples

### ENSIP-15 Tests (`ensip15/tests.json`)

The file contains an array of test objects with various properties:

```json
[
  {
    "name": "version",
    "validated": "2025-09-14T17:56:31.472Z",
    "built": "2025-09-14T17:56:24.099Z",
    "cldr": "47 (2025-08-02T20:26:29.295Z)",
    "derived": "2025-09-14T17:56:22.939Z",
    "ens_hash_base64": "92cbf3a1af3c3c0a91aee0dc542072775f4ebbbc526a84189a12da2d56f5accd",
    "nf_hash_base64": "9ef43cc7215aa7a53e4ed9afa3b4f2f8ce00a2c708b9eb96aa409ae6fa3fb6af",
    "spec_hash": "4febc8f5d285cbf80d2320fb0c1777ac25e378eb72910c34ec963d0a4e319c84",
    "unicode": "17.0.0 (2025-09-10T16:58:18.331Z)",
    "version": "1.11.1"
  },
  {
    "name": "",
    "comment": "Empty"
  },
  {
    "name": " ",
    "error": true,
    "comment": "Empty: Whitespace"
  },
  {
    "name": ".",
    "error": true,
    "comment": "Null Labels"
  },
  {
    "name": ".eth",
    "error": true,
    "comment": "Null 2LD"
  }
]
```

**Test Object Schema:**
- `name` (string): Input string to normalize
- `error` (boolean, optional): If true, normalization should fail
- `comment` (string, optional): Description of the test case
- `norm` (string, optional): Expected normalized output
- `tokens` (array, optional): Expected token breakdown
- First object is metadata with version info

### NF Tests (`nf/nf-tests.json`)

The file contains test cases for Unicode normalization forms:

```json
{
  "Specific cases": [
    ["Ḋ", "Ḋ", "Ḋ"],
    ["Ḍ", "Ḍ", "Ḍ"],
    ["Ḍ̇", "Ḍ̇", "Ḍ̇"]
  ],
  "Character by character test": [
    [" ", " ", " "],
    ["¨", "¨", "¨"],
    ["ª", "ª", "ª"]
  ]
}
```

**Structure:**
- Top-level object with test category keys
- Each category contains an array of test cases
- Each test case is a 3-element array: `[input, nfc_output, nfd_output]`

## File Locations

### Created/Modified Files

- `test-data/` (directory to be created)
- `test-data/ensip15-tests.json` (copied file)
- `test-data/nf-tests.json` (copied file)
- `build.zig` (modified to add copy step)
- `tools/copy_test_data.zig` (optional, if using standalone script approach)

### Source Files (Read-only)

- `go-ens-normalize/ensip15/tests.json`
- `go-ens-normalize/nf/nf-tests.json`

## Dependencies

**None** - This task is standalone and can be completed independently.

## Success Criteria

- [ ] Directory `test-data/` exists at repository root
- [ ] File `test-data/ensip15-tests.json` exists
- [ ] File `test-data/nf-tests.json` exists
- [ ] Files contain valid JSON (can be parsed)
- [ ] Command `zig build copy-test-data` executes successfully
- [ ] Files are byte-for-byte identical to source files
- [ ] Build step completes without errors
- [ ] Files are properly copied even if test-data directory doesn't exist

## Validation Commands

### Run the copy step
```bash
zig build copy-test-data
```

### Verify files exist and check sizes
```bash
ls -lh test-data/
```

Expected output:
```
total 1.2M
-rw-r--r-- 1 user user 850K Oct 30 12:00 ensip15-tests.json
-rw-r--r-- 1 user user 337K Oct 30 12:00 nf-tests.json
```

### Verify valid JSON
```bash
# Check first 20 lines of ensip15 tests
cat test-data/ensip15-tests.json | head -20

# Use jq to validate JSON structure (if available)
jq 'type' test-data/ensip15-tests.json  # Should output: "array"
jq 'keys | .[0]' test-data/nf-tests.json  # Should output: test category name
```

### Verify files are identical to source
```bash
# Compare checksums
sha256sum go-ens-normalize/ensip15/tests.json test-data/ensip15-tests.json
sha256sum go-ens-normalize/nf/nf-tests.json test-data/nf-tests.json

# Or use diff
diff go-ens-normalize/ensip15/tests.json test-data/ensip15-tests.json
diff go-ens-normalize/nf/nf-tests.json test-data/nf-tests.json
```

### Test that it can be re-run safely
```bash
# Run twice to ensure idempotency
zig build copy-test-data
zig build copy-test-data
```

## Common Pitfalls

### 1. File Encoding Issues
**Problem:** JSON files may contain UTF-8 characters that could be corrupted during copy.

**Solution:**
- Ensure binary copy mode is used (Zig's `copyFile` does this by default)
- Verify file integrity with checksums after copying
- Test JSON parsing after copy to catch encoding issues

### 2. Path Dependencies
**Problem:** The `go-ens-normalize/` directory path might vary or not exist.

**Solution:**
- Add error handling for missing source files
- Document that `go-ens-normalize` must be cloned first
- Consider adding a check in the build script:
  ```zig
  std.fs.cwd().access("go-ens-normalize/ensip15/tests.json", .{}) catch {
      std.debug.print("Error: go-ens-normalize not found. Please clone it first.\n", .{});
      return error.SourceNotFound;
  };
  ```

### 3. Permissions Issues
**Problem:** May not have write permissions for test-data directory.

**Solution:**
- Handle directory creation errors gracefully
- Check write permissions before attempting copy
- Provide clear error messages

### 4. File Modification
**Problem:** Accidentally modifying test data files during copy or processing.

**Solution:**
- Never modify the test data files
- Use direct file copy, not read-parse-write
- Consider making copied files read-only:
  ```bash
  chmod 444 test-data/*.json
  ```

### 5. Large File Sizes
**Problem:** NF tests file is 336KB, which may take time to copy or load.

**Solution:**
- This is expected; the file contains comprehensive Unicode test cases
- Ensure adequate memory when loading for tests
- Consider streaming or lazy loading if needed later

### 6. Build Step Dependencies
**Problem:** Build step runs even when files are up-to-date.

**Solution:**
- Use Zig's build system properly to track dependencies
- Consider checking file modification times
- Document that it's safe to re-run (idempotent operation)

### 7. Git Tracking
**Problem:** Should test-data files be committed to git?

**Solution:**
- **Yes**, commit the test data files
- They are essential for the test suite
- They are derived from the reference implementation
- Update them when go-ens-normalize updates
- Add to .gitignore if you prefer to copy on-demand instead

## Additional Notes

### Why Copy Instead of Symlink?

While symlinking might seem simpler, copying has advantages:
1. **Portability**: Works on all platforms (Windows doesn't handle symlinks well)
2. **Independence**: Project works even if go-ens-normalize is moved/deleted
3. **Git-friendly**: Can commit test data with the project
4. **CI/CD**: Easier to set up in continuous integration

### Test Data Updates

When the go-ens-normalize reference implementation updates:
1. Re-run `zig build copy-test-data`
2. Review changes with `git diff test-data/`
3. Update any tests that may be affected
4. Commit the updated test data

### File Size Considerations

- `ensip15-tests.json`: ~850KB (comprehensive normalization tests)
- `nf-tests.json`: ~337KB (extensive Unicode normalization cases)
- Total: ~1.2MB (acceptable for git repository)

## Related Tasks

- **Task 06**: Parse JSON test data in Zig
- **Task 07**: Implement test harness using the test data
- **Task 08**: Run tests and validate against expected results

## References

- [ENSIP-15 Specification](https://docs.ens.domains/ensip/15)
- [go-ens-normalize repository](https://github.com/adraffy/go-ens-normalize)
- [Zig Build System documentation](https://ziglang.org/documentation/master/#Build-System)
