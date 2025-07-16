# Whole-Script Confusable Detection Implementation

## Overview

Whole-script confusables are one of the most critical security features in ENS normalization. They prevent homograph attacks where an attacker creates a domain that looks identical to a legitimate one using characters from different scripts.

## The Attack Vector

**Example Attack:**
- Legitimate: `paypal.eth` (Latin script)
- Malicious: `рауpаl.eth` (Mixed Cyrillic/Latin - looks identical)

Without confusable detection, users could be tricked into interacting with the malicious domain thinking it's the legitimate one.

## How Whole-Script Confusables Work

### Data Structure in spec.zon
```zig
.wholes = .{
    .{
        .valid = .{ 97, 98, 99 },      // Latin: a, b, c
        .confused = .{ 1072, 1073, 1089 } // Cyrillic: а, б, с (look identical)
    },
    // ... more confusable sets
}
```

### Algorithm
1. **Load confusable sets** from `spec.zon`
2. **For each script group**, check if the label uses characters that are confusable with other scripts
3. **If confusables found**, verify all characters in the label belong to the same confusable set
4. **Reject** if characters span multiple confusable sets (mixed confusables)

## Reference Implementation Analysis

### JavaScript Reference (ens-normalize.js)
```javascript
// From ens-normalize.js validate.js
function checkWholeScriptConfusables(codepoints, groups) {
    // Find all groups that contain these codepoints
    let maker = groups.filter(g => codepoints.every(cp => group_has_cp(g, cp)));
    
    if (maker.length === 0) {
        throw new Error('disallowed character');
    }
    
    // Check for confusables
    for (let group of maker) {
        let shared = codepoints.filter(cp => group_has_cp(group, cp));
        if (shared.length > 0) {
            // Check if any other groups contain these shared characters
            for (let g of maker) {
                if (g !== group && shared.every(cp => group_has_cp(g, cp))) {
                    throw new Error(`whole-script confusable: ${group.N}/${g.N}`);
                }
            }
        }
    }
}
```

## Zig Implementation Plan

### 1. Data Structures

```zig
pub const ConfusableSet = struct {
    valid: []const CodePoint,
    confused: []const CodePoint,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ConfusableSet {
        return ConfusableSet{
            .valid = &.{},
            .confused = &.{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ConfusableSet) void {
        self.allocator.free(self.valid);
        self.allocator.free(self.confused);
    }
    
    pub fn contains(self: *const ConfusableSet, cp: CodePoint) bool {
        return std.mem.indexOfScalar(CodePoint, self.valid, cp) != null or
               std.mem.indexOfScalar(CodePoint, self.confused, cp) != null;
    }
};

pub const ConfusableData = struct {
    sets: []ConfusableSet,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) ConfusableData {
        return ConfusableData{
            .sets = &.{},
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *ConfusableData) void {
        for (self.sets) |*set| {
            set.deinit();
        }
        self.allocator.free(self.sets);
    }
};
```

### 2. Loading from ZON

```zig
pub fn loadConfusables(allocator: std.mem.Allocator) !ConfusableData {
    const zon_data = @embedFile("data/spec.zon");
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, zon_data, .{});
    defer parsed.deinit();
    
    const root_obj = parsed.value.object;
    var confusables = ConfusableData.init(allocator);
    
    if (root_obj.get("wholes")) |wholes_value| {
        const wholes_array = wholes_value.array.items;
        confusables.sets = try allocator.alloc(ConfusableSet, wholes_array.len);
        
        for (wholes_array, 0..) |whole_item, i| {
            const whole_obj = whole_item.object;
            var set = ConfusableSet.init(allocator);
            
            if (whole_obj.get("valid")) |valid_value| {
                const valid_array = valid_value.array.items;
                set.valid = try allocator.alloc(CodePoint, valid_array.len);
                for (valid_array, 0..) |cp_value, j| {
                    set.valid[j] = @as(CodePoint, @intCast(cp_value.integer));
                }
            }
            
            if (whole_obj.get("confused")) |confused_value| {
                const confused_array = confused_value.array.items;
                set.confused = try allocator.alloc(CodePoint, confused_array.len);
                for (confused_array, 0..) |cp_value, j| {
                    set.confused[j] = @as(CodePoint, @intCast(cp_value.integer));
                }
            }
            
            confusables.sets[i] = set;
        }
    }
    
    return confusables;
}
```

### 3. Validation Logic

```zig
pub fn checkWholeScriptConfusables(
    codepoints: []const CodePoint,
    confusables: *const ConfusableData,
    script_group: *const script_groups.ScriptGroup
) ValidationError!void {
    // Find all confusable sets that contain ANY of our codepoints
    var matching_sets = std.ArrayList(*const ConfusableSet).init(allocator);
    defer matching_sets.deinit();
    
    for (confusables.sets) |*set| {
        var has_any = false;
        for (codepoints) |cp| {
            if (set.contains(cp)) {
                has_any = true;
                break;
            }
        }
        if (has_any) {
            try matching_sets.append(set);
        }
    }
    
    if (matching_sets.items.len == 0) {
        return; // No confusables found, safe
    }
    
    // Check if we're mixing confusable sets
    for (matching_sets.items) |set1| {
        for (matching_sets.items) |set2| {
            if (set1 == set2) continue;
            
            // Check if both sets contain some of our codepoints
            var has_from_set1 = false;
            var has_from_set2 = false;
            
            for (codepoints) |cp| {
                if (set1.contains(cp)) has_from_set1 = true;
                if (set2.contains(cp)) has_from_set2 = true;
            }
            
            if (has_from_set1 and has_from_set2) {
                return ValidationError.WholeScriptConfusable;
            }
        }
    }
}
```

## Test Cases

### 1. Valid Cases (Should Pass)
```zig
test "confusables - pure Latin" {
    // "hello" - all Latin, no confusables
    const codepoints = [_]CodePoint{ 'h', 'e', 'l', 'l', 'o' };
    // Should pass
}

test "confusables - pure Cyrillic" {
    // "привет" - all Cyrillic, no mixing
    const codepoints = [_]CodePoint{ 0x043F, 0x0440, 0x0438, 0x0432, 0x0435, 0x0442 };
    // Should pass
}
```

### 2. Invalid Cases (Should Fail)
```zig
test "confusables - mixed Latin/Cyrillic" {
    // "pаypal" - 'p' and 'l' are Latin, 'а', 'y', 'а' are Cyrillic
    const codepoints = [_]CodePoint{ 'p', 0x0430, 'y', 'p', 0x0430, 'l' };
    // Should fail with WholeScriptConfusable
}

test "confusables - subtle Greek mixing" {
    // Mixed Latin/Greek that looks identical
    const codepoints = [_]CodePoint{ 'a', 0x03B1 }; // Latin 'a' + Greek 'α'
    // Should fail with WholeScriptConfusable
}
```

### 3. Edge Cases
```zig
test "confusables - empty input" {
    const codepoints = [_]CodePoint{};
    // Should pass (nothing to confuse)
}

test "confusables - single character" {
    const codepoints = [_]CodePoint{ 'a' };
    // Should pass (can't mix with itself)
}

test "confusables - ASCII numbers" {
    // Numbers should be safe across scripts
    const codepoints = [_]CodePoint{ '1', '2', '3' };
    // Should pass
}
```

## Fuzz Testing Strategy

### 1. Property-Based Tests
```zig
test "confusables - property: pure script always passes" {
    // Generate random strings from single script
    // Verify they never trigger confusable errors
    for (0..1000) |_| {
        const script = randomScript();
        const codepoints = randomStringFromScript(script, 10);
        // Should never fail with confusable error
    }
}

test "confusables - property: known confusables always fail" {
    // Take known confusable pairs and mix them
    // Verify they always trigger confusable errors
    for (confusable_pairs) |pair| {
        const mixed = [_]CodePoint{ pair.script1_char, pair.script2_char };
        // Should always fail with WholeScriptConfusable
    }
}
```

### 2. Mutation Testing
```zig
test "confusables - mutation: replace one character" {
    // Take valid string, replace one char with confusable
    const valid_latin = "hello";
    const cyrillic_e = 0x0435; // Cyrillic 'е' (looks like Latin 'e')
    const mutated = "hеllo"; // 'е' is Cyrillic
    // Should fail with WholeScriptConfusable
}
```

### 3. Regression Tests
```zig
test "confusables - known attacks" {
    // Test real-world attack vectors
    const paypal_attack = [_]CodePoint{ 0x0440, 0x0430, 'y', 0x0440, 0x0430, 'l' };
    const google_attack = [_]CodePoint{ 'g', 0x043E, 0x043E, 'g', 'l', 0x0435 };
    // Both should fail
}
```

## Invariants to Maintain

### 1. Security Invariants
- **No mixed confusables**: If a label contains characters from confusable set A and set B, it must be rejected
- **Transitivity**: If A confuses with B, and B confuses with C, then A+C should be rejected
- **Completeness**: All known confusable pairs from Unicode data must be detected

### 2. Functional Invariants
- **Determinism**: Same input always produces same result
- **Performance**: O(n*m) where n=label length, m=confusable sets (reasonable for ENS)
- **Memory safety**: No leaks, proper cleanup of temporary data structures

### 3. Compatibility Invariants
- **Reference parity**: Must match JavaScript reference implementation results exactly
- **Unicode compliance**: Must handle all Unicode confusable characters
- **Future-proof**: Must handle new confusable sets added to spec.zon

## Implementation Priority

1. **Load confusable data** from spec.zon
2. **Basic detection algorithm** - identify if label has confusables
3. **Validation integration** - add to main validator
4. **Comprehensive tests** - all test cases above
5. **Fuzz testing** - property-based and mutation tests
6. **Performance optimization** - if needed after profiling

## Security Impact

This feature prevents some of the most dangerous ENS attacks:
- **Phishing domains** that look identical to legitimate ones
- **Brand impersonation** using confusable characters
- **Financial fraud** through lookalike domain attacks

Without this feature, the ENS normalizer would allow dangerous homograph attacks that could steal users' funds or credentials.