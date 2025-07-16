# z-ens-normalize

A Zig implementation of ENS (Ethereum Name Service) name normalization.

## Description

`z-ens-normalize` is a robust Zig library for normalizing and validating ENS names according to [ENSIP-15](https://docs.ens.domains/ensip/15) specifications. It handles Unicode normalization, validation, and beautification of ENS names ensuring correct, consistent and idempotent behavior.

## Requirements

- Zig 0.14.0 or later

## Installation

### Using Zig Package Manager

Install the dependency using the Zig CLI:

```bash
zig fetch --save https://github.com/evmts/z-ens-normalize/archive/main.tar.gz
```

This will automatically add the dependency to your `build.zig.zon` file.

Then in your `build.zig`:

```zig
const z_ens_normalize = b.dependency("z_ens_normalize", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("ens_normalize", z_ens_normalize.module("ens_normalize"));
```

### Alternative: Specific Version

To install a specific version or tag:

```bash
zig fetch --save https://github.com/evmts/z-ens-normalize/archive/v0.1.0.tar.gz
```

### Local Development

```bash
git clone https://github.com/evmts/z-ens-normalize.git
cd z-ens-normalize
zig build
```

## Usage

```zig
const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Using normalizer to reuse preloaded data
    var normalizer = try ens_normalize.EnsNameNormalizer.init(allocator);
    defer normalizer.deinit();
    
    const name = "🅰️🅱.eth";
    const processed = try normalizer.process(name);
    defer processed.deinit();
    
    const beautified_name = try processed.beautify();
    defer allocator.free(beautified_name);
    
    const normalized_name = try processed.normalize();
    defer allocator.free(normalized_name);

    std.debug.print("Original: {s}\n", .{name});
    std.debug.print("Normalized: {s}\n", .{normalized_name});
    std.debug.print("Beautified: {s}\n", .{beautified_name});

    // Using normalize directly
    const normalized = try normalizer.normalize("Levvv.eth");
    defer allocator.free(normalized);
    std.debug.print("Direct normalize: {s}\n", .{normalized});

    // Handling errors
    const invalid_result = normalizer.normalize("Levvv..eth");
    if (invalid_result) |result| {
        defer allocator.free(result);
        std.debug.print("Unexpected success: {s}\n", .{result});
    } else |err| {
        std.debug.print("Expected error: {}\n", .{err});
    }
}
```

### Convenience Functions

For simple one-off operations, you can use the convenience functions:

```zig
const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Direct normalization
    const normalized = try ens_normalize.normalize(allocator, "Example.eth");
    defer allocator.free(normalized);
    
    // Direct beautification
    const beautified = try ens_normalize.beautify_fn(allocator, "example.eth");
    defer allocator.free(beautified);
    
    // Full processing
    const processed = try ens_normalize.process(allocator, "Example.eth");
    defer processed.deinit();
}
```

## Testing

The crate contains several types of tests:

- Unit tests
- Integration (e2e) tests -- `tests/`
- [Validation ENS docs tests](https://docs.ens.domains/ensip/15#appendix-validation-tests) -- `tests/ens_tests.zig`

To run all tests:

```bash
zig build test
```

To run specific test files:

```bash
zig test tests/ens_tests.zig
```

## Building

### Library

```bash
zig build
```

### C-Compatible Library

This project also provides a C-compatible interface:

```bash
zig build c-lib
```

### Development

For development with debug information:

```bash
zig build -Doptimize=Debug
```

## Roadmap

- [x] Tokenization
- [x] Normalization
- [x] Beautification
- [x] ENSIP-15 Validation Tests
- [ ] Unicode Normalization Tests
- [ ] CLI to update `specs.json` and `nf.json`
- [ ] analog of [ens_cure](https://github.com/namehash/ens-normalize-python?tab=readme-ov-file#ens_cure) function
- [ ] analog of [ens_normalizations](https://github.com/namehash/ens-normalize-python/tree/main?tab=readme-ov-file#ens_normalizations) function

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
