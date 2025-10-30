# Task 04: Copy Binary Spec Files

## Goal

Copy the compressed binary specification files from the Go reference implementation and set up the project structure for using `@embedFile` in Zig. These binary files contain the ENS normalization and Unicode NF specification data that will be embedded directly into the compiled Zig binary.

## Files to Copy

### ENSIP-15 Specification Binary
- **Source**: `/Users/williamcory/z-ens-normalize/go-ens-normalize/ensip15/spec.bin`
- **Destination**: `src/ensip15/spec.bin`

### Unicode NF Specification Binary
- **Source**: `/Users/williamcory/z-ens-normalize/go-ens-normalize/nf/nf.bin`
- **Destination**: `src/nf/nf.bin`

## Implementation Guidance

### Directory Setup
First, create the necessary directory structure:
```bash
mkdir -p src/ensip15
mkdir -p src/nf
```

### Copying Files
Use standard file copy operations to transfer the binary files:
```bash
cp go-ens-normalize/ensip15/spec.bin src/ensip15/spec.bin
cp go-ens-normalize/nf/nf.bin src/nf/nf.bin
```

### Using @embedFile in Zig
In your Zig source code, embed these files using the `@embedFile` builtin:

```zig
// In src/ensip15/ensip15.zig or similar
const spec_bin = @embedFile("spec.bin");

// In src/nf/nf.zig or similar
const nf_bin = @embedFile("nf.bin");
```

**Important Notes**:
- The `@embedFile` path is **relative to the source file** that uses it
- If you call `@embedFile("spec.bin")` from `src/ensip15/ensip15.zig`, it will look for `src/ensip15/spec.bin`
- The embedded data is available as a `[]const u8` at compile time

## File Locations

After completion, these files should exist:
- `/Users/williamcory/z-ens-normalize/src/ensip15/spec.bin`
- `/Users/williamcory/z-ens-normalize/src/nf/nf.bin`

## Dependencies

**None** - This task can be completed independently.

## Success Criteria

- [ ] Directory `src/ensip15/` exists
- [ ] Directory `src/nf/` exists
- [ ] File `src/ensip15/spec.bin` exists and is binary (not empty)
- [ ] File `src/nf/nf.bin` exists and is binary (not empty)
- [ ] Files are identical to Go source (byte-for-byte)
- [ ] `zig build` succeeds (once Zig code references these files)

## Validation Commands

### Check Files Exist and View Sizes
```bash
ls -lh src/ensip15/spec.bin
ls -lh src/nf/nf.bin
```

Expected output should show non-zero file sizes (likely several KB or more).

### Verify Binary File Types
```bash
file src/ensip15/spec.bin
file src/nf/nf.bin
```

Should show these as binary data files.

### Verify Byte-for-Byte Identical Copies
```bash
# Compare checksums
md5 go-ens-normalize/ensip15/spec.bin src/ensip15/spec.bin
md5 go-ens-normalize/nf/nf.bin src/nf/nf.bin

# Or use diff (should produce no output if identical)
diff go-ens-normalize/ensip15/spec.bin src/ensip15/spec.bin
diff go-ens-normalize/nf/nf.bin src/nf/nf.bin
```

### Verify Build Works
```bash
zig build
```

Should complete without errors (assuming the Zig code properly references these files).

## Common Pitfalls

### Don't Modify Binary Files
- These are compressed binary specifications
- Opening them in a text editor may corrupt them
- Always use binary-safe copy operations
- Never commit modified versions to git

### Directory Creation
- Ensure parent directories exist before copying files
- Use `mkdir -p` to create nested directories safely
- Without directories, copy operations will fail

### @embedFile Path Resolution
- The path in `@embedFile()` is relative to the **source file**, not the project root
- If `src/ensip15/ensip15.zig` calls `@embedFile("spec.bin")`, it looks in `src/ensip15/`
- If `src/main.zig` calls `@embedFile("ensip15/spec.bin")`, it looks in `src/ensip15/`
- Plan your module structure accordingly

### File Permissions
- Binary files should be readable (at minimum)
- On Unix systems, ensure proper permissions: `chmod 644 src/**/*.bin`

## Next Steps

After copying these binary files:
1. Create Zig modules that use `@embedFile` to load them
2. Implement decompression logic to parse the binary specifications
3. Build the data structures needed for ENS normalization

## Reference

These binary files are compressed representations of:
- **spec.bin**: ENSIP-15 normalization tables (valid characters, mappings, emoji sequences, etc.)
- **nf.bin**: Unicode Normalization Form (NF) decomposition tables

The Go implementation uses these same files, so we can reference their parsing code as needed.
