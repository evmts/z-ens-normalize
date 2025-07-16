# ENS Normalize Reference Implementations

This document provides an overview of the different ENS normalize implementations available in this repository for reference and comparison.

## Implementation Overview

| Language | Repository | Key Features | Memory Management | Error Handling |
|----------|------------|--------------|------------------|----------------|
| **JavaScript** | `ens-normalize.js/` | Original implementation, most comprehensive | GC managed | Exceptions |
| **Rust** | `src/` (original) | Memory safe, fast | RAII + ownership | Result types |
| **Zig** | `src/` (converted) | Memory safe, explicit | Manual allocators | Error unions |
| **C#** | `ENSNormalize.cs/` | Strongly typed, modern | GC managed | Exceptions |
| **Java** | `ENSNormalize.java/` | Object-oriented, typed | GC managed | Exceptions |
| **Go** | `go-ens-normalize/` | Systems level, performant | Manual management | Error values |
| **Python** | `ens-normalize-python/` | High-level, readable | GC managed | Exceptions |

## Key Implementation Patterns

### 1. Memory Management Approaches

#### **JavaScript** (`ens-normalize.js/src/lib.js`)
```javascript
// Garbage collected, lazy initialization
let MAPPED, IGNORED, CM, NSM, ESCAPE, NFC_CHECK, GROUPS;

function init() {
    if (MAPPED) return;
    // Initialize data structures
    MAPPED = new Map(read_mapped(r));
    IGNORED = read_sorted_set();
    // ...
}
```

#### **Rust** (`src/normalizer.rs`)
```rust
// RAII with automatic cleanup
pub struct EnsNameNormalizer {
    specs: CodePointsSpecs,
}

impl EnsNameNormalizer {
    pub fn new(specs: CodePointsSpecs) -> Self {
        Self { specs }
    }
    // Automatic cleanup when dropped
}
```

#### **Zig** (`src/normalizer.zig`)
```zig
// Explicit allocator management
pub const EnsNameNormalizer = struct {
    specs: code_points.CodePointsSpecs,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, specs: code_points.CodePointsSpecs) EnsNameNormalizer {
        return EnsNameNormalizer{ .specs = specs, .allocator = allocator };
    }
    
    pub fn deinit(self: *EnsNameNormalizer) void {
        self.specs.deinit();
    }
};
```

#### **Go** (`go-ens-normalize/ensip15/ensip15.go`)
```go
// Explicit memory management with sync.Once
type ENSIP15 struct {
    nf                   *nf.NF
    shouldEscape         util.RuneSet
    ignored              util.RuneSet
    // ...
}

var (
    singleton *ENSIP15
    once      sync.Once
)

func New() *ENSIP15 {
    once.Do(func() {
        singleton = &ENSIP15{}
        // Initialize...
    })
    return singleton
}
```

#### **C#** (`ENSNormalize.cs/ENSNormalize/ENSIP15.cs`)
```csharp
// Garbage collected with static initialization
public class ENSIP15 {
    public static readonly NF NF = new(new(Blobs.NF));
    public static readonly ENSIP15 Instance = new(NF, new(Blobs.ENSIP15));
    
    private readonly ReadOnlyIntSet _ignored;
    private readonly ReadOnlyIntSet _combiningMarks;
    // ...
}
```

### 2. Error Handling Strategies

#### **JavaScript** (`ens-normalize.js/src/lib.js`)
```javascript
// Exceptions with descriptive messages
function error_disallowed(cp) {
    return new Error(`disallowed character: ${quoted_cp(cp)}`);
}

function error_group_member(g, cp) {
    let quoted = quoted_cp(cp);
    return new Error(`illegal mixture: ${g.N} + ${quoted}`);
}
```

#### **Rust** (`src/error.rs`)
```rust
// Result types with detailed error information
#[derive(Debug, Clone, thiserror::Error, PartialEq, Eq)]
pub enum ProcessError {
    #[error("contains visually confusing characters from multiple scripts: {0}")]
    Confused(String),
    #[error("invalid character ('{sequence}') at position {index}: {inner}")]
    CurrableError {
        inner: CurrableError,
        index: usize,
        sequence: String,
        maybe_suggest: Option<String>,
    },
}
```

#### **Zig** (`src/error.zig`)
```zig
// Error unions with detailed information
pub const ProcessError = error{
    Confused,
    CurrableError,
    DisallowedSequence,
    OutOfMemory,
};

pub const ProcessErrorInfo = union(ProcessError) {
    Confused: struct { message: []const u8 },
    CurrableError: struct {
        inner: CurrableError,
        index: usize,
        sequence: []const u8,
        maybe_suggest: ?[]const u8,
    },
    // ...
};
```

#### **Go** (`go-ens-normalize/ensip15/errors.go`)
```go
// Error values with context
type DisallowedCharacterError struct {
    cp rune
}

func (e *DisallowedCharacterError) Error() string {
    return fmt.Sprintf("disallowed character: %U", e.cp)
}

type IllegalMixtureError struct {
    group1, group2 string
}

func (e *IllegalMixtureError) Error() string {
    return fmt.Sprintf("illegal mixture: %s + %s", e.group1, e.group2)
}
```

### 3. API Design Patterns

#### **High-Level API** (Most Languages)
```javascript
// JavaScript
ens_normalize("Hello.ETH")     // "hello.eth"
ens_beautify("Hello.ETH")      // "Hello.ETH"

// Rust
normalize("Hello.ETH")?        // "hello.eth"
beautify("Hello.ETH")?         // "Hello.ETH"

// Zig
normalize(allocator, "Hello.ETH")  // "hello.eth"
beautify_fn(allocator, "Hello.ETH") // "Hello.ETH"

// Go
ensip15.Normalize("Hello.ETH") // "hello.eth"
ensip15.Beautify("Hello.ETH")  // "Hello.ETH"
```

#### **Object-Oriented API** (C#, Java)
```csharp
// C#
var normalizer = new ENSIP15();
normalizer.Normalize("Hello.ETH");
normalizer.Beautify("Hello.ETH");

// Java
ENSIP15 normalizer = new ENSIP15();
normalizer.normalize("Hello.ETH");
normalizer.beautify("Hello.ETH");
```

### 4. Data Loading Strategies

#### **JavaScript** - Compressed binary data
```javascript
// Embedded compressed data
import COMPRESSED from './include-ens.js';

function init() {
    let r = read_compressed_payload(COMPRESSED);
    MAPPED = new Map(read_mapped(r));
    // ...
}
```

#### **Rust** - JSON with serde
```rust
// JSON parsing with serde
#[derive(Deserialize)]
pub struct SpecJson {
    pub groups: Vec<Group>,
    pub wholes: HashMap<String, WholeValue>,
}

lazy_static! {
    static ref SPEC: SpecJson = serde_json::from_str(include_str!("spec.json")).unwrap();
}
```

#### **Go** - Embedded binary
```go
// Embedded binary data
//go:embed spec.bin
var compressed []byte

func init() {
    decoder := util.NewDecoder(compressed)
    // Parse binary data...
}
```

#### **C#** - Embedded resources
```csharp
// Embedded binary resources
public static class Blobs {
    public static readonly byte[] NF = LoadResource("nf.bin");
    public static readonly byte[] ENSIP15 = LoadResource("spec.bin");
}
```

## Performance Characteristics

| Language | Startup Time | Memory Usage | Throughput | Notes |
|----------|--------------|--------------|------------|-------|
| **JavaScript** | Medium | Medium | High | JIT compilation benefits |
| **Rust** | Fast | Low | Very High | Zero-cost abstractions |
| **Zig** | Fast | Very Low | Very High | Manual optimization |
| **C#** | Medium | Medium | High | GC overhead |
| **Java** | Slow | High | High | JVM warmup required |
| **Go** | Fast | Low | High | Good for concurrent use |
| **Python** | Slow | High | Medium | Interpreted overhead |

## Testing Strategies

### **Test Data Sources**
- All implementations use the same test data (`tests.json`)
- JavaScript implementation generates the canonical test cases
- Each language adapts the test format to its conventions

### **Test Organization**
- **JavaScript**: HTML test runners + Node.js tests
- **Rust**: `cargo test` with rstest framework
- **Zig**: Built-in test framework
- **C#**: MSTest/NUnit framework
- **Java**: JUnit framework  
- **Go**: Built-in `go test`
- **Python**: pytest framework

## Key Takeaways for Zig Implementation

1. **Memory Management**: Explicit allocators provide fine-grained control
2. **Error Handling**: Error unions offer type-safe error propagation
3. **Performance**: Manual memory management enables optimal performance
4. **Interoperability**: C-compatible ABI for integration with other languages
5. **Compile-time Features**: Comptime can optimize Unicode operations

## Reference Implementation Benefits

Having multiple reference implementations provides:

1. **Cross-validation** of normalization results
2. **Performance benchmarking** across languages
3. **API design patterns** for different use cases
4. **Test case verification** and edge case discovery
5. **Language-specific optimizations** examples

## Usage Recommendations

- **Study JavaScript implementation** for algorithm understanding
- **Reference Go implementation** for memory management patterns
- **Compare C# implementation** for type safety approaches
- **Analyze Java implementation** for object-oriented design
- **Review Python implementation** for high-level algorithm flow
- **Use Rust implementation** for memory safety patterns