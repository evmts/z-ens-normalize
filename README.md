# z-ens-normalize

> Zero-dependency Zig implementation of [ENSIP-15](https://docs.ens.domains/ensip/15): ENS Name Normalization Standard

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A complete port of [go-ens-normalize](https://github.com/adraffy/go-ens-normalize) to Zig, providing ENS (Ethereum Name Service) domain name normalization according to ENSIP-15 specification.

## Features

- **Zero Dependencies** - No external packages required
- **100% ENSIP-15 Compliant** - Passes all official validation tests
- **Embedded Data** - Compressed specification data built into the binary
- **Thread-Safe** - Singleton pattern with lazy initialization via `std.once()`
- **Memory Efficient** - Explicit allocator parameters for full control
- **Unicode 16.0.0** - Latest Unicode standard support
- **C FFI Compatible** - Full C bindings for interoperability
- **WebAssembly Ready** - Browser and Node.js WASM support

## Installation

### Using build.zig.zon

Add to your `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "0.1.0",
    .dependencies = .{
        .z_ens_normalize = .{
            .url = "https://github.com/YOUR_USERNAME/z-ens-normalize/archive/refs/tags/v0.1.0.tar.gz",
            // Use zig fetch to get the correct hash
            .hash = "...",
        },
    },
}
```

### In your build.zig

```zig
const ens = b.dependency("z_ens_normalize", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("z_ens_normalize", ens.module("z_ens_normalize"));
```

## Quick Start

```zig
const std = @import("std");
const ens = @import("z_ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Normalize a name
    const normalized = try ens.normalize(allocator, "Nick.ETH");
    defer allocator.free(normalized);
    std.debug.print("Normalized: {s}\n", .{normalized});
    // Output: "nick.eth"

    // Beautify a name (preserves emoji presentation)
    const beautified = try ens.beautify(allocator, "🚀RaFFY🚴‍♂️.eTh");
    defer allocator.free(beautified);
    std.debug.print("Beautified: {s}\n", .{beautified});
    // Output: "🚀raffy🚴‍♂️.eth"
}
```

## API Reference

### Convenience Functions

These functions use a thread-safe singleton instance initialized lazily on first use:

#### `normalize(allocator: Allocator, name: []const u8) ![]u8`

Normalizes an ENS name according to ENSIP-15 specification.

**Parameters:**
- `allocator` - Memory allocator for the result
- `name` - Input name as UTF-8 bytes

**Returns:** Normalized name (caller owns memory, must free)

**Example:**
```zig
const result = try ens.normalize(allocator, "VITALIK.eth");
defer allocator.free(result);
// result: "vitalik.eth"
```

#### `beautify(allocator: Allocator, name: []const u8) ![]u8`

Beautifies an ENS name with visual enhancements while maintaining normalization.

**Differences from normalize():**
- Preserves FE0F variation selectors for emoji presentation
- Converts lowercase Greek xi (ξ) to uppercase Xi (Ξ) in non-Greek labels
- More visually appealing for UI display

**Example:**
```zig
const result = try ens.beautify(allocator, "🏴‍☠️nick.eth");
defer allocator.free(result);
// result: "🏴‍☠️nick.eth" (with proper emoji presentation)
```

### Instance Methods

For more control, you can use the singleton directly or create your own instance:

#### `shared() *const Ensip15`

Returns the thread-safe singleton instance.

```zig
const instance = ens.shared();
const result = try instance.normalize(allocator, "test.eth");
defer allocator.free(result);
```

#### `Ensip15.init(allocator: Allocator) !Ensip15`

Creates a new ENSIP15 normalizer instance.

```zig
var normalizer = try ens.Ensip15.init(allocator);
defer normalizer.deinit();

const result = try normalizer.normalize(allocator, "test.eth");
defer allocator.free(result);
```

### Error Handling

All normalization functions return errors for invalid input:

```zig
const result = ens.normalize(allocator, "invalid..name") catch |err| switch (err) {
    error.EmptyLabel => std.debug.print("Label cannot be empty\n", .{}),
    error.DisallowedCharacter => std.debug.print("Contains disallowed character\n", .{}),
    error.IllegalMixture => std.debug.print("Illegal script mixture\n", .{}),
    error.WholeConfusable => std.debug.print("Confusable with another name\n", .{}),
    else => return err,
};
```

### Error Types

The library defines the following error types:

- `InvalidLabelExtension` - Label has `--` at positions 2-3 (e.g., "ab--test")
- `IllegalMixture` - Mixed scripts not allowed together
- `WholeConfusable` - Label looks like a different script
- `LeadingUnderscore` - Underscore appears after label start
- `FencedLeading` - Zero-width joiner at label start
- `FencedAdjacent` - Adjacent zero-width characters
- `FencedTrailing` - Zero-width joiner at label end
- `DisallowedCharacter` - Character not allowed in ENS names
- `EmptyLabel` - Zero-length label
- `CMLeading` - Combining mark at label start
- `CMAfterEmoji` - Combining mark after emoji
- `NSMDuplicate` - Duplicate non-spacing marks
- `NSMExcessive` - Too many non-spacing marks
- `OutOfMemory` - Allocation failure
- `InvalidUtf8` - Invalid UTF-8 encoding

## Unicode Normalization

The library also exposes Unicode normalization functions:

```zig
const nf = ens.NF.init();

// NFC (Canonical Composition)
const composed = try nf.nfc(allocator, &[_]u21{ 0x61, 0x300 }); // "à"
defer allocator.free(composed);

// NFD (Canonical Decomposition)
const decomposed = try nf.nfd(allocator, &[_]u21{ 0xE0 }); // "a" + "̀"
defer allocator.free(decomposed);
```

## Testing

The library includes comprehensive test suites:

### Run All Tests

```bash
zig build test
```

### Test Categories

1. **ENSIP-15 Validation Tests** (`tests/ensip15_test.zig`)
   - 100% pass rate on official ENSIP-15 test suite
   - Tests normalization, beautification, and error cases

2. **Unicode Normalization Tests** (`tests/nf_test.zig`)
   - 100% pass rate on Unicode normalization test cases
   - Tests NFC, NFD, and Hangul composition

3. **Initialization Tests** (`tests/init_test.zig`)
   - Tests data loading from embedded binary
   - Validates spec.bin and nf.bin decompression

### Test Data

Test data is automatically copied from the reference implementation:

```bash
zig build copy-test-data
```

This downloads:
- `ensip15-tests.json` - ENSIP-15 validation test cases
- `nf-tests.json` - Unicode normalization test cases

## C FFI Bindings

The library provides a complete C API for interoperability with C/C++ and other languages.

### Building C Library

```bash
# Build C FFI library
zig build c-lib

# Output: zig-out/lib/libz_ens_normalize_c.a
# Header: zig-out/include/z_ens_normalize.h
```

### C API Usage

```c
#include <stdio.h>
#include "z_ens_normalize.h"

int main(void) {
    // Initialize library (optional)
    zens_init();

    // Normalize a name
    ZensResult result = zens_normalize("Nick.ETH", 0);
    if (result.error_code == ZENS_SUCCESS) {
        printf("Normalized: %.*s\n", (int)result.len, result.data);
        zens_free(result);
    } else {
        printf("Error: %s\n", zens_error_message(result.error_code));
    }

    // Cleanup (optional)
    zens_deinit();
    return 0;
}
```

### Compiling C Programs

```bash
# Using GCC
gcc your_program.c -I./zig-out/include -L./zig-out/lib -lz_ens_normalize_c -o your_program

# Using Clang
clang your_program.c -I./zig-out/include -L./zig-out/lib -lz_ens_normalize_c -o your_program
```

### C API Reference

#### Functions

**`int32_t zens_init(void)`**
- Initialize the library (optional but recommended)
- Returns 0 on success

**`void zens_deinit(void)`**
- Cleanup library resources
- Call at program exit

**`ZensResult zens_normalize(const uint8_t *input, size_t input_len)`**
- Normalize an ENS name
- `input_len` can be 0 to use strlen()
- Returns `ZensResult` with normalized name or error

**`ZensResult zens_beautify(const uint8_t *input, size_t input_len)`**
- Beautify an ENS name with visual enhancements
- Same parameters as `zens_normalize()`

**`void zens_free(ZensResult result)`**
- Free memory allocated by normalize/beautify
- Must be called for successful results

**`const char* zens_error_message(int32_t error_code)`**
- Get human-readable error message
- Returns static string (do not free)

#### Error Codes

```c
typedef enum {
    ZENS_SUCCESS = 0,
    ZENS_ERROR_OUT_OF_MEMORY = -1,
    ZENS_ERROR_INVALID_UTF8 = -2,
    ZENS_ERROR_INVALID_LABEL_EXTENSION = -3,
    ZENS_ERROR_ILLEGAL_MIXTURE = -4,
    ZENS_ERROR_WHOLE_CONFUSABLE = -5,
    ZENS_ERROR_LEADING_UNDERSCORE = -6,
    ZENS_ERROR_DISALLOWED_CHARACTER = -10,
    ZENS_ERROR_EMPTY_LABEL = -11,
    // ... more error codes
} ZensErrorCode;
```

See `include/z_ens_normalize.h` for complete API documentation.

## WebAssembly

The library can be compiled to WebAssembly for use in browsers and Node.js.

### Building WebAssembly

```bash
# Build for browsers/Node.js (freestanding)
zig build wasm
# Output: zig-out/bin/z_ens_normalize.wasm

# Build with WASI support
zig build wasi
# Output: zig-out/bin/z_ens_normalize_wasi.wasm

# Build both
zig build wasm-all
```

### Browser Usage

```html
<!DOCTYPE html>
<html>
<body>
    <script type="module">
        // Load WASM module
        const response = await fetch('z_ens_normalize.wasm');
        const bytes = await response.arrayBuffer();
        const { instance } = await WebAssembly.instantiate(bytes, {});

        // Initialize
        instance.exports.zens_init();

        // Helper to encode string
        const encoder = new TextEncoder();
        function normalize(name) {
            const bytes = encoder.encode(name);
            const ptr = instance.exports.malloc(bytes.length);
            const memory = new Uint8Array(instance.exports.memory.buffer);
            memory.set(bytes, ptr);

            const resultPtr = instance.exports.zens_normalize(ptr, bytes.length);
            // ... read result from memory
        }

        console.log(normalize("Nick.ETH")); // "nick.eth"
    </script>
</body>
</html>
```

### Node.js Usage

```javascript
import { readFile } from 'fs/promises';

// Load WASM
const wasmBuffer = await readFile('z_ens_normalize.wasm');
const { instance } = await WebAssembly.instantiate(wasmBuffer, {});

// Initialize
instance.exports.zens_init();

// Use normalize/beautify functions (see examples/example_node.mjs)
```

### WASM Examples

Complete examples are provided in the `examples/` directory:

- **`examples/example.html`** - Browser example with interactive UI
- **`examples/example_node.mjs`** - Node.js example with ES modules
- **`examples/example.c`** - C API example

Run the examples:

```bash
# C example
zig build c-lib
gcc examples/example.c -I./zig-out/include -L./zig-out/lib -lz_ens_normalize_c -o example
./example

# Node.js example
zig build wasm
node examples/example_node.mjs

# Browser example
zig build wasm
# Serve examples/ directory with HTTP server
python -m http.server 8000
# Open http://localhost:8000/examples/example.html
```

## Build Process

### Standard Build

```bash
# Build library
zig build

# Run tests
zig build test

# Build with optimizations
zig build -Doptimize=ReleaseFast
```

### Cross-Compilation

```bash
# Build for specific target
zig build -Dtarget=x86_64-linux

# Build static library for all targets
zig build --summary all
```

### All Build Targets

```bash
zig build              # Default library
zig build test         # Run tests
zig build c-lib        # C FFI library
zig build wasm         # WebAssembly (freestanding)
zig build wasi         # WebAssembly (WASI)
zig build wasm-all     # All WASM variants
```

### Development Workflow

1. **Sync with reference implementation:**
   ```bash
   # Update test data from go-ens-normalize
   zig build copy-test-data
   ```

2. **Run tests:**
   ```bash
   zig build test
   ```

3. **Build library:**
   ```bash
   zig build
   # Output: zig-out/lib/libz_ens_normalize.a
   ```

## Architecture

### Directory Structure

```
z-ens-normalize/
├── src/
│   ├── root.zig              # Public Zig API & singleton
│   ├── root_c.zig            # C FFI bindings
│   ├── ensip15/
│   │   ├── ensip15.zig       # Main normalization logic
│   │   ├── init.zig          # Data initialization
│   │   ├── types.zig         # Core data structures
│   │   ├── errors.zig        # Error definitions
│   │   ├── utils.zig         # Helper utilities
│   │   └── spec.bin          # Embedded ENSIP-15 data
│   ├── nf/
│   │   ├── nf.zig            # Unicode normalization
│   │   └── nf.bin            # Embedded normalization data
│   └── util/
│       ├── decoder.zig       # Binary data decoder
│       └── runeset.zig       # Efficient rune set
├── include/
│   └── z_ens_normalize.h     # C API header
├── examples/
│   ├── example.c             # C API example
│   ├── example.html          # Browser WASM example
│   └── example_node.mjs      # Node.js WASM example
├── tests/
│   ├── ensip15_test.zig      # ENSIP-15 validation tests
│   ├── nf_test.zig           # Unicode normalization tests
│   └── init_test.zig         # Initialization tests
├── test-data/
│   ├── ensip15-tests.json    # ENSIP-15 test cases
│   └── nf-tests.json         # NF test cases
├── build.zig                 # Build configuration
└── README.md                 # This file
```

### Development Process

This library was developed using **AI-assisted implementation** with [Claude Code](https://claude.com/claude-code), following a structured, multi-phase approach:

#### Context & Specifications

- **`.claude/commands/ens.md`** - Complete ENS specification context including ENSIP-1 (ENS Protocol) and ENSIP-15 (Name Normalization) standards
- **`prompts/`** - 19 detailed implementation guides (tasks 01-19) providing step-by-step instructions for porting each component from the Go reference implementation

#### Implementation Strategy

The development followed a **staged approach** outlined in `prompts/00-meta-guide.md`:

**Stage 1: Skeleton Setup** (Tasks 01-19)
- Created project structure with all type definitions and function signatures
- Stubbed all logic with `@panic("TODO")` to achieve compilation
- Result: `zig build` succeeds, tests exist but fail

**Stage 2: Implementation** (Dependency order)
- Implemented actual logic following the Go reference implementation
- Three parallel phases:
  - **Phase 1 (Foundation)**: 8 concurrent tasks - decoder, runeset, types, binaries, test data
  - **Phase 2 (Core)**: 8 concurrent tasks - NF initialization, normalization, ENSIP15 validation
  - **Phase 3 (Tests)**: 3 concurrent tasks - test infrastructure for NF and ENSIP15
- Result: `zig build test` shows 100% pass rate

#### Key Implementation Guides

Each prompt file in `prompts/` includes:
- Complete Go reference code to port
- Zig type mappings and patterns
- Step-by-step implementation guidance
- Success criteria checklist
- Validation commands

Example tasks:
- `01-util-decoder.md` - Binary data decoder for compressed spec files
- `09-nf-init.md` - Unicode normalization data initialization
- `13-ensip15-normalize.md` - Core ENSIP-15 normalization pipeline
- `18-ensip15-tests.md` - Comprehensive validation test suite

This approach enabled systematic development with clear milestones, parallel workstreams, and automated validation at each stage.

### Memory Management

The library follows Zig best practices for memory management:

- **Explicit Allocators** - All allocation-requiring functions take `Allocator` parameter
- **Caller Owns Memory** - Functions return owned slices that must be freed
- **No Hidden Allocations** - No global allocator usage
- **Zero-Copy Initialization** - Embedded data is referenced, not copied

Example memory pattern:
```zig
// Caller provides allocator and owns result
const result = try ens.normalize(allocator, "test.eth");
defer allocator.free(result); // Caller frees memory

// Internal operations use the provided allocator
// No global state or hidden allocations
```

## Performance

The library is designed for efficiency:

- **Compressed Data** - Spec data is bit-packed and compressed
- **Embedded Binary** - No file I/O at runtime
- **Lazy Initialization** - Singleton initialized only when first used
- **Zero-Copy Where Possible** - References embedded data directly

## Compatibility

- **Zig Version:** 0.13.0 or later
- **Unicode Version:** 16.0.0
- **ENSIP-15:** Final specification
- **Reference Implementation:** [go-ens-normalize](https://github.com/adraffy/go-ens-normalize) v0.1.1

## Contributing

Contributions are welcome! This implementation aims to maintain 100% compatibility with the reference Go implementation.

### Development Guidelines

1. Run tests before submitting PR: `zig build test`
2. Follow Zig style conventions
3. Add tests for new functionality
4. Update documentation as needed

## License

MIT License - see LICENSE file for details

## Credits

- **Reference Implementation:** [adraffy/go-ens-normalize](https://github.com/adraffy/go-ens-normalize)
- **JavaScript Reference:** [adraffy/ens-normalize.js](https://github.com/adraffy/ens-normalize.js)
- **ENSIP-15 Specification:** [ENS Improvement Proposals](https://docs.ens.domains/ensip/15)
- **Zig Port:** William Cory

## Resources

- [ENSIP-15 Specification](https://docs.ens.domains/ensip/15)
- [ENS Documentation](https://docs.ens.domains/)
- [Unicode Technical Report #15](https://unicode.org/reports/tr15/) (Normalization Forms)
- [Unicode Technical Report #46](https://unicode.org/reports/tr46/) (IDNA Compatibility)
- [Zig Language Reference](https://ziglang.org/documentation/master/)

## Support

- **Issues:** [GitHub Issues](https://github.com/YOUR_USERNAME/z-ens-normalize/issues)
- **ENS Discord:** [discord.gg/ensdomains](https://discord.gg/ensdomains)

---

Built with [Zig](https://ziglang.org/) 🦎
