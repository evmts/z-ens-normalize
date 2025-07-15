# ENS Normalize Zig Implementation

This is a Zig implementation of ENS (Ethereum Name Service) normalization, converted from the original Rust implementation. The project aims to provide memory-safe, performant ENS name normalization with explicit memory management.

## Project Structure

```
src/
├── root.zig           # Main library entry point
├── main.zig           # Executable demo
├── constants.zig      # Constants and code points
├── error.zig          # Error types and formatting
├── utils.zig          # Utility functions
├── tokens.zig         # Token types and tokenization
├── code_points.zig    # Code point handling and groups
├── validate.zig       # Validation logic
├── normalizer.zig     # Main normalization API
├── beautify.zig       # Beautification functions
├── join.zig           # Label joining functions
└── static_data.zig    # Static data structures

tests/
└── ens_tests.zig      # Test cases converted from Rust

build.zig              # Build configuration
build.zig.zon          # Package configuration
```

## Features

- **Memory Safety**: Explicit memory management with allocators
- **Type Safety**: Strong typing with Zig's type system
- **Performance**: Designed for efficiency with minimal allocations
- **Compatibility**: API structure similar to the Rust implementation
- **Testing**: Comprehensive test suite including integration tests

## Memory Management

The Zig implementation uses explicit memory management through allocators, similar to how Rust manages memory but with manual control:

- **Allocators**: All functions that allocate memory take an `allocator` parameter
- **Ownership**: Clear ownership semantics with `deinit()` methods
- **RAII**: Resource cleanup through defer statements
- **Arena Allocation**: Uses arena allocators for temporary allocations

## API Usage

### Basic Usage

```zig
const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Normalize a name
    const normalized = try ens_normalize.normalize(allocator, "Hello.ETH");
    defer allocator.free(normalized);
    
    // Beautify a name
    const beautified = try ens_normalize.beautify_fn(allocator, "ξ.eth");
    defer allocator.free(beautified);
}
```

### Advanced Usage

```zig
const std = @import("std");
const ens_normalize = @import("ens_normalize");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Create a normalizer instance
    var normalizer = ens_normalize.EnsNameNormalizer.default(allocator);
    defer normalizer.deinit();
    
    // Tokenize input
    const tokenized = try normalizer.tokenize("hello.eth");
    defer tokenized.deinit(allocator);
    
    // Process name
    const processed = try normalizer.process("hello.eth");
    defer processed.deinit();
    
    // Get normalized and beautified versions
    const normalized = try processed.normalize();
    defer allocator.free(normalized);
    
    const beautified = try processed.beautify();
    defer allocator.free(beautified);
}
```

## Building and Testing

### Build

```bash
zig build
```

### Run

```bash
zig build run
```

### Test

```bash
zig build test
```

## Current Status

This is a **foundational implementation** that provides:

✅ **Complete Project Structure**: All modules and build configuration
✅ **Memory Management**: Proper allocator usage and cleanup
✅ **API Compatibility**: Similar interface to Rust implementation
✅ **Basic Tokenization**: Simple tokenization logic
✅ **Type Safety**: Strong typing with Zig's type system
✅ **Test Framework**: Comprehensive test suite structure

### What's Implemented

- Basic project structure and build system
- Core data types (CodePoint, tokens, errors)
- Memory-safe API with explicit allocators
- Basic tokenization and validation framework
- Test infrastructure with multiple test suites

### What's Missing

- Full Unicode normalization (NFC/NFD)
- Complete ENS validation rules
- Emoji sequence handling
- Script group detection
- Whole-script confusable checking
- Static data loading from JSON files
- Full error handling with detailed messages

## Implementation Notes

### Memory Management Strategy

The Zig implementation follows these principles:

1. **Explicit Allocators**: All memory allocations use passed allocators
2. **Clear Ownership**: Each structure has clear ownership with `deinit()` methods
3. **RAII Pattern**: Uses `defer` statements for cleanup
4. **Arena Allocation**: Temporary allocations use arena allocators for bulk cleanup

### Differences from Rust

- **Manual Memory Management**: Explicit allocator usage vs. Rust's automatic management
- **Error Handling**: Zig's error unions vs. Rust's Result type
- **Type System**: Zig's comptime vs. Rust's generics
- **String Handling**: Zig's `[]const u8` vs. Rust's `String`/`&str`

### Performance Considerations

- Uses `std.ArrayList` for dynamic arrays with controlled growth
- Employs `std.HashMapUnmanaged` for efficient lookups
- Minimizes allocations through careful memory reuse
- Uses arena allocators for temporary data

## Future Work

To complete this implementation, the following components need to be added:

1. **Unicode Normalization**: Full NFC/NFD implementation
2. **Static Data**: Loading and parsing of ENS normalization data
3. **Validation Rules**: Complete implementation of ENSIP-15 rules
4. **Emoji Handling**: Proper emoji sequence detection and validation
5. **Script Analysis**: Group detection and confusable checking
6. **Error Messages**: Detailed error reporting with suggestions
7. **Performance Optimization**: Benchmarking and optimization
8. **Documentation**: Complete API documentation

## Reference Implementations

This repository contains multiple reference implementations for comparison and learning:

### Available Reference Implementations

- **`ens-normalize.js/`** - Original JavaScript implementation by adraffy
  - Most comprehensive and authoritative implementation
  - Contains extensive Unicode data and derivation tools
  - Includes full test suites and validation data

- **`ENSNormalize.cs/`** - C# implementation by adraffy
  - Strongly typed implementation with modern C# features
  - Good example of memory-safe implementation patterns
  - Includes comprehensive test coverage

- **`ENSNormalize.java/`** - Java implementation by adraffy
  - Object-oriented design with strong typing
  - Demonstrates JVM-based implementation patterns
  - Includes Gradle build system and documentation

- **`go-ens-normalize/`** - Go implementation by adraffy
  - Systems-level implementation with explicit memory management
  - Good reference for performance-oriented design
  - Includes comprehensive benchmarks

- **`ens-normalize-python/`** - Python implementation by namehash
  - High-level implementation with clean API
  - Good for understanding algorithm flow
  - Includes Jupyter notebook examples

### Using Reference Implementations

These implementations are automatically cloned and available for reference:

```bash
# Compare implementations
ls -la ens-normalize.js/src/
ls -la ENSNormalize.cs/ENSNormalize/
ls -la ENSNormalize.java/lib/src/main/java/io/github/adraffy/ens/
ls -la go-ens-normalize/ensip15/
ls -la ens-normalize-python/ens_normalize/
```

### Key Files for Reference

- **JavaScript**: `ens-normalize.js/src/lib.js` - Core implementation
- **C#**: `ENSNormalize.cs/ENSNormalize/ENSNormalize.cs` - Main API
- **Java**: `ENSNormalize.java/lib/src/main/java/io/github/adraffy/ens/ENSNormalize.java` - Main API
- **Go**: `go-ens-normalize/ensip15/ensip15.go` - Core implementation
- **Python**: `ens-normalize-python/ens_normalize/normalization.py` - Main implementation

### Implementation Patterns

Each reference implementation provides insights into:

1. **Memory Management**: How different languages handle Unicode data
2. **Error Handling**: Various approaches to validation errors
3. **API Design**: Different ways to structure the public interface
4. **Performance**: Language-specific optimizations
5. **Testing**: Comprehensive test suite patterns

## Contributing

This implementation serves as a foundation for a full ENS normalization library in Zig. Contributions are welcome, particularly in:

- Implementing missing Unicode normalization functions
- Adding comprehensive validation rules
- Improving error handling and messages
- Optimizing performance and memory usage
- Adding more comprehensive tests
- Learning from reference implementations in other languages

## License

This implementation follows the same license as the original Rust implementation.