# CLAUDE.md - Critical Rules for ENS Normalization Implementation

## 🚨 MANDATORY IMPLEMENTATION RULES

### 1. **ALWAYS Reference Implementations First**
- **NEVER** implement based on assumptions or general understanding
- **ALWAYS** read the reference implementation code BEFORE writing any code
- **ALWAYS** check multiple reference implementations to understand the pattern
- If reference implementations differ, investigate WHY and document the reason

### 2. **Production Parity is NON-NEGOTIABLE**
- A 90% solution is WORSE than no solution
- The implementation MUST match reference implementations 100%
- Every edge case handled by references MUST be handled identically
- No shortcuts, no "good enough", no "we'll fix it later"

### 3. **Data Must Match Exactly**
- Character mappings MUST be identical to reference data
- DO NOT create simplified mappings - use the exact data from references
- If ℌ maps to 'h' in the reference, it MUST map to 'h' (not 'H') in our implementation
- Always check the actual data files (spec.json, include-ens.js) not just the code

### 4. **Test Against Reference Test Cases**
- Every reference implementation has test cases - USE THEM
- Our implementation MUST pass ALL reference test cases
- If a test fails, the implementation is WRONG (not the test)
- Add test cases from ALL reference implementations, not just one

### 5. **No Assumptions About Unicode**
- DO NOT assume how Unicode normalization works
- DO NOT assume how character mappings should work
- Look at EXACTLY how the references handle it
- Copy their approach precisely

## 📋 Implementation Checklist

Before implementing ANY feature:

- [ ] Read the JavaScript reference implementation
- [ ] Read the Rust reference implementation  
- [ ] Read at least one other reference (Go, C#, or Java)
- [ ] Understand the data format they use
- [ ] Copy their test cases
- [ ] Verify our approach matches theirs EXACTLY

## 🔍 Common Pitfalls to Avoid

1. **Incomplete Mappings**: References map ℌ→h directly, not ℌ→H→h
2. **Missing Edge Cases**: Every character the references handle must be handled
3. **Wrong Assumptions**: Don't assume ASCII folding is separate from Unicode mappings

## ⚠️ **CRITICAL MEMORY MANAGEMENT RULES**

### **ArrayList + toOwnedSlice() Pattern - EXTREMELY DANGEROUS**

**NEVER do this:**
```zig
var list = std.ArrayList(T).init(allocator);
defer list.deinit(); // ❌ BUG: Creates double-free!
// ... add items to list ...
return list.toOwnedSlice(); // Transfers ownership, then defer tries to free again
```

**CORRECT patterns:**

**Option 1 - No defer, handle errors manually:**
```zig
var list = std.ArrayList(T).init(allocator);
errdefer list.deinit(); // Only free on error
// ... add items to list ...
return list.toOwnedSlice(); // Transfer ownership on success
```

**Option 2 - Use defer with careful ownership:**
```zig
var list = std.ArrayList(T).init(allocator);
defer list.deinit();
// ... add items to list ...
const result = try list.toOwnedSlice();
list = std.ArrayList(T).init(allocator); // Reset to empty so deinit is safe
return result;
```

### **Why This Matters:**
- `toOwnedSlice()` transfers ownership of internal buffer to caller
- `defer deinit()` then tries to free the SAME buffer
- Results in double-free bugs, bus errors, memory corruption
- Can cause mysterious crashes, segfaults, data corruption

### **Memory Management Checklist:**
- [ ] Every `allocator.alloc()` has corresponding `allocator.free()`
- [ ] Every `allocator.dupe()` has corresponding `allocator.free()`
- [ ] Never call `deinit()` after `toOwnedSlice()` on same ArrayList
- [ ] Use `errdefer` for cleanup on error paths
- [ ] Test with allocation failure modes (if possible)
4. **Incomplete Testing**: Test with actual ENS names from production, not just simple cases

## 🛠️ Debugging Process

When something doesn't work:

1. **First**: Check what the JavaScript implementation does
2. **Second**: Verify against the Rust implementation
3. **Third**: Look at the actual data files they use
4. **Fourth**: Run their test cases
5. **Never**: Assume or guess how it should work

## 📊 Data Sources Priority

1. **Primary**: The actual spec.json or include-ens.js data files
2. **Secondary**: The test cases in reference implementations
3. **Tertiary**: The implementation code itself
4. **Never**: Our own interpretation or simplification

## ⚠️ Red Flags

These indicate you're doing it wrong:

- "This should work the same way"
- "We can simplify this"
- "We'll handle this case later"
- "90% compatibility is fine for now"
- Creating our own test data instead of using reference data
- Implementing without reading the references first

## 🎯 Success Criteria

An implementation is ONLY complete when:

1. It passes ALL test cases from ALL reference implementations
2. It uses the EXACT same character mapping data
3. It handles EVERY edge case the references handle
4. It produces IDENTICAL output for all inputs
5. There are NO "known limitations" compared to references

## 💡 Key Insight from Character Mappings Failure

We failed because:
- We assumed ℌ→H→h (two-step) when references do ℌ→h (one-step)
- We created "basic mappings" instead of using the actual data
- We didn't check what the actual mapping data contained
- We marked it "complete" with known limitations

This must NEVER happen again. Always use the reference data and implementation exactly.

## 🔧 Specific Technical Rules

### Character Mappings
- Use the EXACT mappings from spec.json or include-ens.js
- Do NOT create simplified versions
- Do NOT assume multi-step transformations
- Mathematical symbols map DIRECTLY to lowercase (ℌ→h, not ℌ→H)

### Tokenization
- Token types must match references exactly
- Token ordering must match references exactly  
- Edge cases (empty strings, special chars) must match references exactly

### Validation
- Validation rules must match references exactly
- Error types must match references exactly
- Label types must match references exactly

### Testing
- MUST include test cases from JavaScript implementation
- MUST include test cases from Rust implementation
- MUST include test cases from at least one other implementation
- MUST test with real ENS names from mainnet

Remember: The goal is 100% compatibility with existing implementations. Nothing less is acceptable.

## 🚫 CRITICAL: Data Format Rules

### ZON vs JSON
- **WE USE ZON FILES, NOT JSON**
- The project has already been converted from JSON to ZON
- **NEVER** suggest converting ZON back to JSON
- **NEVER** try to parse ZON as JSON at runtime
- **NEVER** create JSON-to-ZON or ZON-to-JSON converters

### Why This Matters
- We specifically converted from JSON to ZON for good reasons
- Going back to JSON is moving backwards
- Converting between formats at runtime is inefficient and error-prone
- If ZON import isn't working, we need to fix the ZON import, not abandon it

### Correct Approaches for ZON
1. Use `@import` with proper type definitions at compile time
2. Define proper Zig types that match the ZON structure
3. Handle heterogeneous arrays with union types or other Zig constructs
4. Use comptime code generation if needed

### What NOT to Do
- ❌ Convert ZON to JSON at runtime
- ❌ Revert to JSON files
- ❌ Parse ZON as text and transform it
- ❌ Suggest "easier" solutions that involve JSON

The project uses ZON. Period. Make it work with ZON.

## 🔧 Zig Build System Rules

### Adding Tests
When creating new test files, you MUST add them to build.zig:
1. Tests need to import the main module using `@import("ens_normalize")`
2. In build.zig, each test must be added with the module dependency:
   ```zig
   const my_test = b.addTest(.{
       .root_source_file = .{ .path = "tests/my_test.zig" },
       .target = target,
       .optimize = optimize,
   });
   my_test.root_module.addImport("ens_normalize", ens_normalize_module);
   ```
3. Never try to run tests directly with `zig test` - always use `zig build test`

### Module System
- The main module is defined in build.zig as `ens_normalize_module`
- All tests must import it as `@import("ens_normalize")`
- Individual source files cannot be tested in isolation if they depend on the module