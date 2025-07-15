# Script Group Validation Implementation Plan

## Overview

Script group validation is a critical security feature in ENS normalization that prevents homograph attacks and ensures labels use consistent scripts. This document outlines the implementation plan based on the reference implementations.

## Current Status

- ✅ Basic group structure exists (`ParsedGroup` in code_points.zig)
- ✅ Loading valid characters from groups for character mappings
- ❌ Full group data not loaded (name, restricted status, CM rules)
- ❌ Script mixing detection not implemented
- ❌ Confusable detection not implemented
- ❌ Combining mark validation per group not implemented

## Reference Implementation Analysis

### JavaScript (ens-normalize.js)

```javascript
// Group structure from lib.js
GROUPS = read_array_while(i => {
    let N = read_array_while(r).map(x => x+0x60); // name
    if (N.length) {
        let R = i >= unrestricted; // restricted flag
        N[0] -= 32; // capitalize
        N = str_from_cps(N);
        if (R) N=`Restricted[${N}]`;
        let P = read_chunked(); // primary
        let Q = read_chunked(); // secondary  
        let M = !r(); // NSM check needed
        return {N, P, Q, M, R};
    }
});

// Script mixing check
function determine_group(unique) {
    let groups = GROUPS;
    for (let cp of unique) {
        let gs = groups.filter(g => group_has_cp(g, cp));
        if (!gs.length) {
            throw error_disallowed(cp);
        }
        groups = gs;
        if (gs.length == 1) break;
    }
    return groups;
}

// Confusable check
function check_whole(group, unique) {
    // Complex whole-script confusable detection
}
```

### Rust (ens-normalize-rs)

```rust
pub struct Group {
    pub name: String,
    pub restricted: bool,
    pub primary: HashSet<u32>,
    pub secondary: HashSet<u32>,
    pub cm_whitelist: HashSet<u32>,
}

fn find_group(&self, cps: &[u32]) -> Result<&Group, ProcessError> {
    let mut groups: Vec<&Group> = self.groups.iter().collect();
    
    for &cp in cps {
        let matching_groups: Vec<&Group> = groups
            .iter()
            .filter(|g| g.contains(cp))
            .cloned()
            .collect();
            
        if matching_groups.is_empty() {
            return Err(ProcessError::DisallowedCharacter(cp));
        }
        
        groups = matching_groups;
        if groups.len() == 1 {
            break;
        }
    }
    
    Ok(groups[0])
}
```

## Key Features to Implement

### 1. Load Complete Group Data

From spec.json groups array:
- Group name (decode from compressed format)
- Restricted flag
- Primary codepoints
- Secondary codepoints  
- CM whitelist flag (M field)

### 2. Script Mixing Detection

Algorithm:
1. Collect unique codepoints from label (excluding emoji, ignored)
2. Find all groups containing first codepoint
3. For each subsequent codepoint, filter to groups containing it
4. If no groups remain, throw "illegal mixture" error
5. If only one group remains, that's the script

### 3. Confusable Detection

Two types:
1. **Mixed Script Confusables**: Detected during script mixing check
2. **Whole Script Confusables**: Check if entire label could be confused with another script

### 4. Combining Mark Validation

- Check combining marks are valid for the detected script
- Apply NSM (non-spacing mark) rules:
  - Max 4 consecutive NSM
  - No duplicate NSM in sequence
  - Script-specific CM whitelists

### 5. Error Messages

Proper error messages for:
- `illegal mixture: Latin + Cyrillic`
- `disallowed character: {cp}`
- `whole-script confusable: Latin/Cyrillic`
- `excessive non-spacing marks`
- `duplicate non-spacing marks`

## Implementation Steps

### Step 1: Update Group Loading

```zig
pub const ScriptGroup = struct {
    name: []const u8,
    restricted: bool,
    primary: std.AutoHashMap(CodePoint, void),
    secondary: std.AutoHashMap(CodePoint, void),
    cm_whitelist: ?std.AutoHashMap(CodePoint, void),
    check_nsm: bool,
    allocator: std.mem.Allocator,
};

pub fn loadScriptGroups(allocator: std.mem.Allocator) ![]ScriptGroup {
    // Load from spec.json groups array
    // Decode compressed names
    // Set restricted flag based on position
    // Load primary/secondary sets
    // Handle CM whitelist
}
```

### Step 2: Implement Script Detection

```zig
pub fn determineScriptGroup(groups: []const ScriptGroup, unique_cps: []const CodePoint) !*const ScriptGroup {
    var remaining_groups = try allocator.alloc(*const ScriptGroup, groups.len);
    defer allocator.free(remaining_groups);
    
    // Copy all groups initially
    for (groups, 0..) |*group, i| {
        remaining_groups[i] = group;
    }
    var remaining_count = groups.len;
    
    // Filter by each codepoint
    for (unique_cps) |cp| {
        var new_count: usize = 0;
        for (remaining_groups[0..remaining_count]) |group| {
            if (group.containsCp(cp)) {
                remaining_groups[new_count] = group;
                new_count += 1;
            }
        }
        
        if (new_count == 0) {
            return error.IllegalMixture;
        }
        
        remaining_count = new_count;
        if (remaining_count == 1) break;
    }
    
    return remaining_groups[0];
}
```

### Step 3: Add Confusable Detection

```zig
pub fn checkWholeScriptConfusable(group: *const ScriptGroup, unique_cps: []const CodePoint, whole_map: *const WholeMap) !void {
    // Implementation based on reference whole-script confusable algorithm
}
```

### Step 4: Enhance CM Validation

```zig
pub fn validateCombiningMarks(group: *const ScriptGroup, cps: []const CodePoint) !void {
    if (!group.check_nsm) return;
    
    // Apply NSM rules
    // Check consecutive NSM count
    // Check for duplicates
    // Validate against group's CM whitelist
}
```

## Test Cases

### Mixed Scripts
- `"abc123абв"` - Latin + Cyrillic (should fail)
- `"hello世界"` - Latin + Han (should fail)
- `"αβγ"` - Greek only (should pass)

### Confusables
- `"vitalik"` (Latin) vs `"vіtalіk"` (with Cyrillic і)
- Whole script confusables between similar scripts

### Combining Marks
- `"éééé"` - Valid combining marks
- `"e̴̵̶̷̸"` - Excessive combining marks (should fail)
- `"é́"` - Duplicate combining marks (should fail)

### Edge Cases
- Empty labels
- Single character labels
- Labels with only emoji
- Labels with ignored characters

## Next Steps After Implementation

1. **Enhanced Validation**: Complete remaining validation rules
2. **Official Test Vectors**: Run against ENS test suite
3. **Performance Optimization**: Optimize group lookups
4. **Better Error Messages**: Include character details in errors