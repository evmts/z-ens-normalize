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