# Task 15: Create Public Root Module API

## Goal

Create the public API in `src/root.zig` that exposes ENSIP15 functionality with both instance-based and convenience singleton patterns. This file serves as the main entry point for the library, providing a clean and ergonomic API for users.

## Go Reference Code

The Go implementation in `go-ens-normalize/ensip15/shared.go` shows the singleton pattern:

```go
package ensip15

import (
	"sync"
)

var shared *ENSIP15
var once sync.Once

func Shared() *ENSIP15 {
	once.Do(func() {
		shared = New()
	})
	return shared
}

func Normalize(name string) string {
	s, err := Shared().Normalize(name)
	if err != nil {
		panic(err)
	}
	return s
}

func Beautify(name string) string {
	s, err := Shared().Beautify(name)
	if err != nil {
		panic(err)
	}
	return s
}
```

**Key observations:**
- Uses `sync.Once` for thread-safe lazy initialization
- `Shared()` returns a singleton instance
- Convenience functions (`Normalize`, `Beautify`) use the singleton
- Convenience functions panic on error (Zig should return errors instead)
- Singleton is initialized on first call to `Shared()`

## Implementation Guidance

### 1. Re-export Core Types

The root module should re-export the main types from internal modules:

```zig
pub const Ensip15 = @import("ensip15/ensip15.zig").Ensip15;
pub const Error = @import("ensip15/errors.zig").Error;
```

### 2. Implement Thread-Safe Singleton

Use Zig's `std.Thread.Once` for thread-safe lazy initialization:

```zig
const std = @import("std");

var singleton_once = std.Thread.Once{};
var singleton_instance: Ensip15 = undefined;

fn initSingleton() void {
    singleton_instance = Ensip15.init() catch |err| {
        // Handle initialization error
        @panic("Failed to initialize ENSIP15 singleton");
    };
}
```

### 3. Provide Singleton Access

```zig
/// Returns a shared singleton instance of Ensip15.
/// Thread-safe: uses lazy initialization on first call.
/// The singleton is initialized only once across all threads.
pub fn shared() *const Ensip15 {
    singleton_once.call(initSingleton);
    return &singleton_instance;
}
```

### 4. Convenience Functions

Provide ergonomic wrapper functions that use the singleton:

```zig
/// Normalizes an ENS name using the shared singleton instance.
/// Returns a newly allocated normalized string.
/// Caller owns the returned memory and must free it.
pub fn normalize(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return shared().normalize(allocator, name);
}

/// Beautifies an ENS name using the shared singleton instance.
/// Returns a newly allocated beautified string.
/// Caller owns the returned memory and must free it.
pub fn beautify(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return shared().beautify(allocator, name);
}
```

**Important differences from Go:**
- Zig returns errors instead of panicking
- Allocator must be passed explicitly (no hidden allocations)
- Caller is responsible for freeing returned memory
- Document ownership clearly

## Public API Design

The complete public API should look like:

```zig
const std = @import("std");

// Re-export main struct
pub const Ensip15 = @import("ensip15/ensip15.zig").Ensip15;

// Re-export error types
pub const Error = @import("ensip15/errors.zig").Error;

// Singleton implementation
var singleton_once = std.Thread.Once{};
var singleton_instance: Ensip15 = undefined;

fn initSingleton() void {
    singleton_instance = Ensip15.init() catch |err| {
        @panic("Failed to initialize ENSIP15 singleton");
    };
}

/// Returns a shared singleton instance of Ensip15.
/// Thread-safe: uses lazy initialization on first call.
pub fn shared() *const Ensip15 {
    singleton_once.call(initSingleton);
    return &singleton_instance;
}

/// Normalizes an ENS name using the shared singleton instance.
/// Returns a newly allocated normalized string.
/// Caller owns the returned memory and must free it.
pub fn normalize(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return shared().normalize(allocator, name);
}

/// Beautifies an ENS name using the shared singleton instance.
/// Returns a newly allocated beautified string.
/// Caller owns the returned memory and must free it.
pub fn beautify(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    return shared().beautify(allocator, name);
}
```

## File Location

- **Primary file**: `/Users/williamcory/z-ens-normalize/src/root.zig`

This is the main entry point that users will import.

## Dependencies

This task requires the following to be completed:

- **Task 07**: Error types (`src/ensip15/errors.zig`)
- **Task 11**: ENSIP15 struct and init() method (`src/ensip15/ensip15.zig`)
- **Task 13**: normalize() method on Ensip15 struct
- **Task 14**: beautify() method on Ensip15 struct

All of these must be implemented before this task can be completed.

## Success Criteria

- [ ] File `src/root.zig` created or modified
- [ ] `Ensip15` struct re-exported from `ensip15/ensip15.zig`
- [ ] `Error` types re-exported from `ensip15/errors.zig`
- [ ] `shared()` function defined and returns singleton instance
- [ ] `normalize()` convenience function defined
- [ ] `beautify()` convenience function defined
- [ ] Thread-safe singleton initialization using `std.Thread.Once`
- [ ] Singleton returns `*const Ensip15` (const pointer)
- [ ] All public functions have doc comments (///)
- [ ] Doc comments describe ownership and memory management
- [ ] File compiles without errors
- [ ] `zig build` succeeds

## Validation Commands

After implementation, validate with:

```bash
# Verify the project builds
zig build

# Check for compilation errors
zig build-lib src/root.zig

# Run tests (if any)
zig build test
```

## Common Pitfalls

1. **Thread Safety**:
   - Must use `std.Thread.Once` for singleton initialization
   - Don't use simple boolean flags or manual locking
   - `std.Thread.Once.call()` handles all synchronization

2. **Singleton Lifetime**:
   - Singleton should be `var`, not `const`
   - Return `*const Ensip15` from `shared()` (const pointer to prevent mutation)
   - Initialize as `undefined` and set in `initSingleton()`

3. **Lazy Initialization**:
   - Don't call `init()` at compile time or startup
   - Only initialize on first call to `shared()`
   - Handle initialization errors (panic is acceptable for singleton)

4. **Function Delegation**:
   - Convenience functions should just delegate to singleton methods
   - Don't duplicate logic
   - Keep them thin wrappers

5. **Documentation**:
   - All public items must have doc comments (`///`)
   - Document memory ownership clearly
   - Explain that caller must free returned memory
   - Document thread-safety guarantees

6. **Re-exports**:
   - Use syntax: `pub const X = @import(...).X;`
   - Don't wrap or modify re-exported types
   - Keep them simple aliases

7. **Error Handling**:
   - Convenience functions return errors (don't panic like Go)
   - Only panic in singleton initialization if truly unrecoverable
   - Document error conditions

8. **Allocator Pattern**:
   - Convenience functions must take `allocator` parameter
   - Can't hide allocations from caller
   - This is a key difference from Go

## Additional Notes

- This is the **main entry point** for library users
- Keep it clean and well-documented
- The API should feel natural to Zig programmers
- Users can choose between:
  - Creating their own `Ensip15` instances
  - Using the singleton via `shared()`
  - Using convenience functions for common operations

## Example Usage

After implementation, users should be able to use the library like:

```zig
const ens = @import("ens-normalize");
const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Option 1: Use convenience function
    const normalized = try ens.normalize(allocator, "Nick.ETH");
    defer allocator.free(normalized);

    // Option 2: Use singleton directly
    const instance = ens.shared();
    const beautified = try instance.beautify(allocator, "nick.eth");
    defer allocator.free(beautified);

    // Option 3: Create own instance
    const my_instance = try ens.Ensip15.init();
    const result = try my_instance.normalize(allocator, "test");
    defer allocator.free(result);
}
```
