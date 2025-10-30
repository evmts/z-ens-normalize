# Task 16: Complete Build System Setup

## Goal

Create a comprehensive `build.zig` that integrates all modules, tests, and build steps into a cohesive build system. This build file should properly organize the project structure, handle dependencies, run tests, and provide a clean interface for building and validating the z-ens-normalize library.

## Current Build.zig

The existing build.zig is minimal:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // const optimize = b.standardOptimizeOption(.{});
    const mod = b.addModule("z_ens_normalize", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
```

This needs to be expanded to include optimization options, proper test integration, data file copying, and additional build steps.

## Implementation Guidance

### Module Structure

The project follows this structure:

```
z_ens_normalize (root: src/root.zig)
├── util/
│   ├── decoder.zig       # UTF-8 decoding utilities
│   └── runeset.zig       # Rune set data structures
├── nf/
│   └── nf.zig           # Unicode normalization (NF and NFD)
└── ensip15/
    ├── types.zig        # Core types (Label, Token, etc.)
    ├── errors.zig       # Error definitions
    ├── ensip15.zig      # Main ENSIP-15 implementation
    └── utils.zig        # Helper utilities
```

### Key Concepts

1. **Module Definition**: The main library module that exposes the public API
2. **Test Integration**: How to run unit tests and integration tests
3. **Build Steps**: Custom steps for copying data files and other operations
4. **Target/Optimization**: Proper configuration for different platforms and optimization levels
5. **Dependencies**: How tests depend on the main module

## Build Steps Needed

Your build.zig should support the following commands:

- `zig build` - Build the library (compile check)
- `zig build test` - Run all unit tests
- `zig build copy-test-data` - Copy test JSON files to zig-out/
- `zig build --help` - Show all available build steps

## Implementation Details

### 1. Standard Options

```zig
const target = b.standardTargetOptions(.{});
const optimize = b.standardOptimizeOption(.{});
```

Uncomment and use the `optimize` option to allow users to choose optimization levels (Debug, ReleaseSafe, ReleaseFast, ReleaseSmall).

### 2. Module Definition

The main module should be defined with:
- Name: "z_ens_normalize"
- Root source file: "src/root.zig"
- Target and optimize options

The root.zig file should export all public APIs:
```zig
pub const ensip15 = @import("ensip15/ensip15.zig");
pub const nf = @import("nf/nf.zig");
pub const util = @import("util/decoder.zig");
// ... etc
```

### 3. Test Configuration

Tests should:
- Use the main module as root_module
- Run with `zig build test`
- Include all test files in the project

Test files to integrate:
- `src/util/decoder_test.zig`
- `src/util/runeset_test.zig`
- `src/nf/nf_test.zig`
- `src/ensip15/types_test.zig`
- `src/ensip15/ensip15_test.zig`
- Any integration tests

### 4. Data File Copying

Some tests require JSON data files (test-data/*.json). Create a build step to copy these:

```zig
const copy_test_data = b.step("copy-test-data", "Copy test data files to zig-out/");
```

This step should:
- Create the destination directory if it doesn't exist
- Copy all JSON files from test-data/ to zig-out/test-data/
- Be a dependency of the test step (so tests can find the files)

### 5. Library Build Step (Optional)

For users who want to explicitly build the library:

```zig
const lib = b.addStaticLibrary(.{
    .name = "z_ens_normalize",
    .root_source_file = b.path("src/root.zig"),
    .target = target,
    .optimize = optimize,
});
b.installArtifact(lib);
```

## File Location

`/Users/williamcory/z-ens-normalize/build.zig`

## Dependencies

This task depends on:
- **Phase 1** (Tasks 01-05): Core utilities and data structures
- **Phase 2** (Tasks 06-10): Unicode normalization
- **Phase 3** (Tasks 11-15): ENSIP-15 implementation
- **Test Files**: All *_test.zig files created in previous phases
- **Test Data**: JSON files in test-data/ directory

## Success Criteria

- [ ] build.zig properly structured with comments
- [ ] Module created with root.zig as entry point
- [ ] Optimize option uncommented and used
- [ ] All source files accessible through module
- [ ] Test step configured to run all tests
- [ ] Copy test data step configured (if test data exists)
- [ ] Target and optimize options set correctly
- [ ] `zig build` succeeds (compile check passes)
- [ ] `zig build test` runs (tests may fail initially, that's expected)
- [ ] `zig build --help` shows all available steps with descriptions
- [ ] Module can be imported by other projects

## Validation Commands

Run these commands to verify the build system works:

```bash
# Show available build steps
zig build --help

# Build the library (compile check)
zig build

# Run all tests (they may fail, but should run)
zig build test

# Copy test data (if applicable)
zig build copy-test-data

# Build with different optimization levels
zig build -Doptimize=ReleaseFast
zig build -Doptimize=ReleaseSmall
zig build -Doptimize=ReleaseSafe
```

## Common Pitfalls

### 1. Module Dependencies
Modules must be explicitly added if your code imports external packages. For this project, we only use the standard library, so no external dependencies are needed.

### 2. Test Root Module
When creating tests, use `root_module` to reference the main module:
```zig
const mod_tests = b.addTest(.{
    .root_module = mod,
});
```

### 3. @embedFile Paths
Paths in `@embedFile` are relative to the source file, not the project root. For example:
```zig
// In src/nf/nf.zig
const data = @embedFile("nf_data.json"); // Looks in src/nf/
```

### 4. Build Artifact Types
- `addModule`: Creates a reusable module (library code)
- `addTest`: Creates a test executable
- `addExecutable`: Creates a standalone executable
- `addStaticLibrary` / `addSharedLibrary`: Creates a compiled library

Choose the right artifact type for each purpose.

### 5. Step Dependencies
Build steps can depend on each other. For example, tests should depend on data copying:
```zig
test_step.dependOn(&copy_data_step.step);
```

### 6. Directory Creation
When copying files, ensure the destination directory exists:
```zig
const install_dir = b.getInstallPath(.prefix, "test-data");
std.fs.cwd().makePath(install_dir) catch |err| {
    std.debug.print("Failed to create directory: {}\n", .{err});
};
```

### 7. Build Cache
Zig's build system caches results. If something seems wrong, try:
```bash
rm -rf zig-cache zig-out
zig build
```

## Build.zig Structure Template

Here's a recommended structure for your build.zig:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    // 1. Standard options
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 2. Main module definition
    const mod = b.addModule("z_ens_normalize", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 3. Optional: Static library for distribution
    const lib = b.addStaticLibrary(.{
        .name = "z_ens_normalize",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // 4. Test configuration
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_mod_tests.step);

    // 5. Optional: Copy test data step
    const copy_test_data = b.step("copy-test-data", "Copy test data files");
    // ... implement file copying logic ...

    // Make tests depend on data copying
    // test_step.dependOn(copy_test_data);
}
```

## Module Dependency Graph

```
z_ens_normalize (root.zig)
│
├─→ ensip15/ensip15.zig (main API)
│   ├─→ ensip15/types.zig
│   ├─→ ensip15/errors.zig
│   ├─→ ensip15/utils.zig
│   ├─→ nf/nf.zig (for normalization)
│   └─→ util/decoder.zig (for UTF-8 handling)
│
├─→ nf/nf.zig (normalization)
│   ├─→ util/decoder.zig
│   └─→ util/runeset.zig
│
└─→ util/
    ├─→ decoder.zig (UTF-8 utilities)
    └─→ runeset.zig (rune set operations)
```

All dependencies are internal to the project - no external packages needed.

## Documentation Generation (Optional)

Zig can generate documentation from your code comments. Add this step if desired:

```zig
const docs = b.addStaticLibrary(.{
    .name = "z_ens_normalize",
    .root_source_file = b.path("src/root.zig"),
    .target = target,
    .optimize = .Debug,
});

const docs_step = b.step("docs", "Generate documentation");
const install_docs = b.addInstallDirectory(.{
    .source_dir = docs.getEmittedDocs(),
    .install_dir = .prefix,
    .install_subdir = "docs",
});
docs_step.dependOn(&install_docs.step);
```

Run with: `zig build docs`

## Expected Output

After running `zig build --help`, you should see:

```
Steps:
  install (default)      Copy build artifacts to prefix path
  uninstall              Remove build artifacts from prefix path
  test                   Run all unit tests
  copy-test-data         Copy test data files
  docs                   Generate documentation (if implemented)
```

After running `zig build`, you should see:

```
Build summary: X compile errors, 0 out of X files failed to emit.
```

Or if successful:
```
Build summary: 0 compile errors, X out of X files successfully emitted.
```

## Notes

- The build system should be clean and well-commented
- Each step should have a descriptive help message
- Consider future maintainers who will read this file
- Test the build system on a clean checkout
- Document any non-obvious choices in comments

## Next Steps After Completion

Once the build system is complete:
1. Run `zig build` to verify compilation
2. Run `zig build test` to see which tests pass/fail
3. Fix any compilation errors revealed by the build
4. Iterate on failing tests
5. Document the build commands in README.md

The build system is the foundation for all development work - make it solid!
