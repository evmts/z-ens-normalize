# Trie-Based Emoji Matching Design Document

## Overview

This document outlines the design for implementing a trie-based emoji matching system for the ENS normalization library, following the Java reference implementation's approach for optimal performance.

## Background

The current implementation uses a hash map-based approach for emoji matching, which has O(n²) worst-case complexity when checking all possible emoji sequences. The Java reference implementation uses a trie (prefix tree) for O(n) emoji matching performance.

### Current Implementation Issues

1. **Performance**: Hash map lookup requires checking all possible prefixes of input
2. **Memory**: Stores duplicate prefix data across multiple emoji entries
3. **Scalability**: Performance degrades with increasing number of emoji sequences

## Reference Implementation Analysis

### Java Reference Trie Structure

From `/reference/ENSNormalize.java/lib/src/main/java/io/github/adraffy/ens/ENSIP15.java`:

```java
static class EmojiNode {
    EmojiSequence emoji;
    HashMap<Integer, EmojiNode> map;
    
    EmojiNode then(int cp) {
        if (map == null) map = new HashMap<>();
        EmojiNode node = map.get(cp);
        if (node == null) {
            node = new EmojiNode();
            map.put(cp, node);
        }
        return node;
    }
}
```

### Trie Construction Algorithm

```java
// precompute: emoji trie
final EmojiNode emojiRoot = new EmojiNode();
for (EmojiSequence emoji: emojis) {
    ArrayList<EmojiNode> nodes = new ArrayList<>();
    nodes.add(emojiRoot);
    
    for (int cp: emoji.beautified.array) {
        if (cp == 0xFE0F) {
            // Special handling for FE0F: duplicate all current nodes
            for (int i = 0, e = nodes.size(); i < e; i++) {
                nodes.add(nodes.get(i).then(cp));
            }
        } else {
            // Regular codepoint: advance all nodes
            for (int i = 0, e = nodes.size(); i < e; i++) {
                nodes.set(i, nodes.get(i).then(cp));
            }
        }
    }
    
    // Mark all final nodes as containing this emoji
    for (EmojiNode x: nodes) {
        x.emoji = emoji;
    }
}
```

### Emoji Matching Algorithm

```java
EmojiResult findEmoji(int[] cps, int i) {
    EmojiNode node = emojiRoot;
    EmojiResult last = null;
    
    for (int e = cps.length; i < e; ) {
        if (node.map == null) break;
        node = node.map.get(cps[i++]);
        if (node == null) break;
        
        if (node.emoji != null) {
            last = new EmojiResult(i, node.emoji); 
        }
    }
    return last;
}
```

## Zig Implementation Design

### Core Data Structures

```zig
const std = @import("std");
const CodePoint = u32;
const EmojiSequence = @import("emoji.zig").EmojiData;

/// Trie node for emoji matching
pub const EmojiTrieNode = struct {
    /// Emoji sequence if this node is a terminal
    emoji: ?EmojiSequence,
    /// Child nodes mapped by codepoint
    children: std.AutoHashMap(CodePoint, *EmojiTrieNode),
    /// Allocator for memory management
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) EmojiTrieNode {
        return EmojiTrieNode{
            .emoji = null,
            .children = std.AutoHashMap(CodePoint, *EmojiTrieNode).init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *EmojiTrieNode) void {
        // Recursively free all child nodes
        var iterator = self.children.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.children.deinit();
    }
    
    /// Get or create child node for given codepoint
    pub fn getOrCreateChild(self: *EmojiTrieNode, cp: CodePoint) !*EmojiTrieNode {
        if (self.children.get(cp)) |child| {
            return child;
        }
        
        const child = try self.allocator.create(EmojiTrieNode);
        child.* = EmojiTrieNode.init(self.allocator);
        try self.children.put(cp, child);
        return child;
    }
    
    /// Get child node for given codepoint
    pub fn getChild(self: *const EmojiTrieNode, cp: CodePoint) ?*EmojiTrieNode {
        return self.children.get(cp);
    }
    
    /// Check if this node has any children
    pub fn hasChildren(self: *const EmojiTrieNode) bool {
        return self.children.count() > 0;
    }
    
    /// Set emoji sequence for this node
    pub fn setEmoji(self: *EmojiTrieNode, emoji: EmojiSequence) void {
        self.emoji = emoji;
    }
    
    /// Check if this node is a terminal (has emoji)
    pub fn isTerminal(self: *const EmojiTrieNode) bool {
        return self.emoji != null;
    }
};

/// Emoji matching result
pub const EmojiMatch = struct {
    /// Position after the matched emoji
    pos: usize,
    /// Matched emoji sequence
    emoji: EmojiSequence,
    /// Length of match in bytes
    byte_len: usize,
    /// Length of match in codepoints
    cp_len: usize,
};

/// Emoji trie for efficient prefix matching
pub const EmojiTrie = struct {
    root: EmojiTrieNode,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) EmojiTrie {
        return EmojiTrie{
            .root = EmojiTrieNode.init(allocator),
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *EmojiTrie) void {
        self.root.deinit();
    }
    
    /// Insert emoji sequence into trie
    pub fn insert(self: *EmojiTrie, emoji: EmojiSequence) !void {
        var nodes = std.ArrayList(*EmojiTrieNode).init(self.allocator);
        defer nodes.deinit();
        
        try nodes.append(&self.root);
        
        for (emoji.emoji) |cp| {
            if (cp == 0xFE0F) {
                // Special FE0F handling: duplicate all current nodes
                const current_count = nodes.items.len;
                for (0..current_count) |i| {
                    const new_node = try nodes.items[i].getOrCreateChild(cp);
                    try nodes.append(new_node);
                }
            } else {
                // Regular codepoint: advance all nodes
                for (nodes.items, 0..) |node, i| {
                    nodes.items[i] = try node.getOrCreateChild(cp);
                }
            }
        }
        
        // Mark all final nodes as containing this emoji
        for (nodes.items) |node| {
            node.setEmoji(emoji);
        }
    }
    
    /// Find longest emoji match starting at given position
    pub fn findLongestMatch(self: *const EmojiTrie, cps: []const CodePoint, start_pos: usize) ?EmojiMatch {
        var node = &self.root;
        var last_match: ?EmojiMatch = null;
        var pos = start_pos;
        
        while (pos < cps.len) {
            if (node.getChild(cps[pos])) |child| {
                node = child;
                pos += 1;
                
                if (node.isTerminal()) {
                    last_match = EmojiMatch{
                        .pos = pos,
                        .emoji = node.emoji.?,
                        .byte_len = 0, // Will be calculated by caller
                        .cp_len = pos - start_pos,
                    };
                }
            } else {
                break;
            }
        }
        
        return last_match;
    }
};
```

### Integration with Existing System

```zig
/// Enhanced emoji map with trie support
pub const EmojiMap = struct {
    /// Trie for efficient prefix matching
    trie: EmojiTrie,
    /// All emoji sequences for iteration
    all_emojis: std.ArrayList(EmojiSequence),
    /// Maximum emoji sequence length
    max_length: usize,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) EmojiMap {
        return EmojiMap{
            .trie = EmojiTrie.init(allocator),
            .all_emojis = std.ArrayList(EmojiSequence).init(allocator),
            .max_length = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *EmojiMap) void {
        self.trie.deinit();
        for (self.all_emojis.items) |emoji| {
            emoji.deinit(self.allocator);
        }
        self.all_emojis.deinit();
    }
    
    /// Add emoji sequence to both trie and list
    pub fn addEmoji(self: *EmojiMap, no_fe0f: []const CodePoint, canonical: []const CodePoint) !void {
        const emoji_data = EmojiSequence{
            .emoji = try self.allocator.dupe(CodePoint, canonical),
            .no_fe0f = try self.allocator.dupe(CodePoint, no_fe0f),
        };
        
        try self.trie.insert(emoji_data);
        try self.all_emojis.append(emoji_data);
        
        if (canonical.len > self.max_length) {
            self.max_length = canonical.len;
        }
    }
    
    /// Find emoji at given position using trie
    pub fn findEmojiAt(self: *const EmojiMap, allocator: std.mem.Allocator, input: []const u8, pos: usize) ?EmojiMatch {
        if (pos >= input.len) return null;
        
        // Convert UTF-8 to codepoints starting from position
        const remaining = input[pos..];
        const cps = utils.str2cps(allocator, remaining) catch return null;
        defer allocator.free(cps);
        
        if (self.trie.findLongestMatch(cps, 0)) |match| {
            // Calculate byte length of match
            const utf8_len = std.unicode.utf8CountCodepoints(input[pos..]) catch return null;
            const match_bytes = if (match.cp_len < utf8_len) blk: {
                var byte_count: usize = 0;
                var cp_count: usize = 0;
                var i: usize = pos;
                
                while (i < input.len and cp_count < match.cp_len) {
                    const char_len = std.unicode.utf8ByteSequenceLength(input[i]) catch break;
                    i += char_len;
                    cp_count += 1;
                }
                
                break :blk i - pos;
            } else remaining.len;
            
            return EmojiMatch{
                .pos = pos + match_bytes,
                .emoji = match.emoji,
                .byte_len = match_bytes,
                .cp_len = match.cp_len,
            };
        }
        
        return null;
    }
};
```

## Performance Analysis

### Time Complexity
- **Trie Construction**: O(total_emoji_codepoints)
- **Emoji Matching**: O(max_emoji_length) per position
- **Overall Tokenization**: O(n * max_emoji_length) where n is input length

### Space Complexity
- **Trie Storage**: O(unique_prefixes * sizeof(EmojiTrieNode))
- **Memory Overhead**: Each node stores HashMap + optional emoji reference
- **Worst Case**: O(total_emoji_codepoints) nodes

### Comparison with Hash Map Approach

| Metric | Hash Map | Trie |
|--------|----------|------|
| Match Time | O(max_emoji_length²) | O(max_emoji_length) |
| Memory Usage | O(emoji_count * avg_length) | O(unique_prefixes) |
| Construction | O(emoji_count) | O(total_codepoints) |
| Prefix Sharing | None | Optimal |

## Test Cases from Reference Implementation

### Basic Emoji Tests
```zig
test "trie basic emoji matching" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var trie = EmojiTrie.init(allocator);
    defer trie.deinit();
    
    // Insert thumbs up emoji
    const thumbs_up = EmojiSequence{
        .emoji = &[_]CodePoint{0x1F44D},
        .no_fe0f = &[_]CodePoint{0x1F44D},
    };
    try trie.insert(thumbs_up);
    
    // Test matching
    const input = [_]CodePoint{0x1F44D, 0x1F3FB}; // thumbs up + skin tone
    const match = trie.findLongestMatch(&input, 0);
    
    try testing.expect(match != null);
    try testing.expectEqual(@as(usize, 1), match.?.pos);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{0x1F44D}, match.?.emoji.emoji);
}
```

### FE0F Handling Tests
```zig
test "trie FE0F variation handling" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var trie = EmojiTrie.init(allocator);
    defer trie.deinit();
    
    // Insert emoji with FE0F variations
    const heart = EmojiSequence{
        .emoji = &[_]CodePoint{0x2764, 0xFE0F}, // ❤️
        .no_fe0f = &[_]CodePoint{0x2764},       // ❤
    };
    try trie.insert(heart);
    
    // Test both with and without FE0F
    const input_with_fe0f = [_]CodePoint{0x2764, 0xFE0F};
    const input_without_fe0f = [_]CodePoint{0x2764};
    
    const match1 = trie.findLongestMatch(&input_with_fe0f, 0);
    const match2 = trie.findLongestMatch(&input_without_fe0f, 0);
    
    try testing.expect(match1 != null);
    try testing.expect(match2 != null);
    try testing.expectEqual(@as(usize, 2), match1.?.pos);
    try testing.expectEqual(@as(usize, 1), match2.?.pos);
}
```

### Complex Emoji Sequence Tests
```zig
test "trie complex emoji sequences" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var trie = EmojiTrie.init(allocator);
    defer trie.deinit();
    
    // Insert complex ZWJ sequence: 👨‍💻 (man technologist)
    const man_technologist = EmojiSequence{
        .emoji = &[_]CodePoint{0x1F468, 0x200D, 0x1F4BB},
        .no_fe0f = &[_]CodePoint{0x1F468, 0x200D, 0x1F4BB},
    };
    try trie.insert(man_technologist);
    
    // Insert overlapping sequence: 👨 (man)
    const man = EmojiSequence{
        .emoji = &[_]CodePoint{0x1F468},
        .no_fe0f = &[_]CodePoint{0x1F468},
    };
    try trie.insert(man);
    
    // Test longest match preference
    const input = [_]CodePoint{0x1F468, 0x200D, 0x1F4BB, 0x0041}; // man technologist + A
    const match = trie.findLongestMatch(&input, 0);
    
    try testing.expect(match != null);
    try testing.expectEqual(@as(usize, 3), match.?.pos);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{0x1F468, 0x200D, 0x1F4BB}, match.?.emoji.emoji);
}
```

### Integration Tests from Java Reference
```zig
test "trie integration with tokenizer" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var emoji_map = EmojiMap.init(allocator);
    defer emoji_map.deinit();
    
    // Add various emoji from Java test cases
    try emoji_map.addEmoji(&[_]CodePoint{0x1F4A9}, &[_]CodePoint{0x1F4A9}); // 💩
    try emoji_map.addEmoji(&[_]CodePoint{0x1F6B4, 0x200D, 0x2642}, &[_]CodePoint{0x1F6B4, 0x200D, 0x2642, 0xFE0F}); // 🚴‍♂️
    
    // Test cases from Java Tests.java
    const test_cases = [_]struct {
        input: []const u8,
        expected_emojis: usize,
    }{
        .{ .input = "💩Raffy", .expected_emojis = 1 },
        .{ .input = "RaFFY🚴‍♂️", .expected_emojis = 1 },
        .{ .input = "💩⌚", .expected_emojis = 1 }, // Should find first emoji
    };
    
    for (test_cases) |case| {
        const match = emoji_map.findEmojiAt(allocator, case.input, 0);
        if (case.expected_emojis > 0) {
            try testing.expect(match != null);
        } else {
            try testing.expect(match == null);
        }
    }
}
```

## Fuzz Testing Strategy

### Property-Based Testing
```zig
/// Fuzz test for trie correctness
test "trie fuzz correctness" {
    const testing = std.testing;
    var prng = std.rand.DefaultPrng.init(0);
    const random = prng.random();
    
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    for (0..1000) |_| {
        var trie = EmojiTrie.init(allocator);
        defer trie.deinit();
        
        var reference_map = std.StringHashMap(EmojiSequence).init(allocator);
        defer reference_map.deinit();
        
        // Generate random emoji sequences
        const emoji_count = random.intRangeAtMost(usize, 1, 100);
        for (0..emoji_count) |_| {
            const seq_len = random.intRangeAtMost(usize, 1, 10);
            var sequence = try allocator.alloc(CodePoint, seq_len);
            defer allocator.free(sequence);
            
            for (sequence) |*cp| {
                cp.* = random.intRangeAtMost(CodePoint, 0x1F300, 0x1F6FF);
            }
            
            const emoji = EmojiSequence{
                .emoji = try allocator.dupe(CodePoint, sequence),
                .no_fe0f = try allocator.dupe(CodePoint, sequence),
            };
            
            try trie.insert(emoji);
            
            const key = try codePointsToString(allocator, sequence);
            defer allocator.free(key);
            try reference_map.put(try allocator.dupe(u8, key), emoji);
        }
        
        // Test random lookups
        for (0..100) |_| {
            const lookup_len = random.intRangeAtMost(usize, 1, 20);
            var lookup_seq = try allocator.alloc(CodePoint, lookup_len);
            defer allocator.free(lookup_seq);
            
            for (lookup_seq) |*cp| {
                cp.* = random.intRangeAtMost(CodePoint, 0x1F300, 0x1F6FF);
            }
            
            const trie_result = trie.findLongestMatch(lookup_seq, 0);
            
            // Verify against reference implementation
            var longest_match: ?EmojiSequence = null;
            var match_len: usize = 0;
            
            for (1..lookup_seq.len + 1) |len| {
                const prefix = lookup_seq[0..len];
                const key = try codePointsToString(allocator, prefix);
                defer allocator.free(key);
                
                if (reference_map.get(key)) |emoji| {
                    longest_match = emoji;
                    match_len = len;
                }
            }
            
            if (longest_match) |expected| {
                try testing.expect(trie_result != null);
                try testing.expectEqual(match_len, trie_result.?.pos);
                try testing.expectEqualSlices(CodePoint, expected.emoji, trie_result.?.emoji.emoji);
            } else {
                try testing.expect(trie_result == null);
            }
        }
    }
}
```

### Performance Benchmarks
```zig
test "trie performance benchmark" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Load real emoji data
    var emoji_map = try loadRealEmojiData(allocator);
    defer emoji_map.deinit();
    
    const test_input = "Hello 👋 World 🌍 with 🚀 emojis 😀 everywhere!";
    
    // Benchmark trie-based matching
    var timer = try std.time.Timer.start();
    
    const iterations = 10000;
    for (0..iterations) |_| {
        var pos: usize = 0;
        while (pos < test_input.len) {
            if (emoji_map.findEmojiAt(allocator, test_input, pos)) |match| {
                pos = match.pos;
            } else {
                pos += 1;
            }
        }
    }
    
    const elapsed = timer.read();
    const ns_per_iteration = elapsed / iterations;
    
    std.debug.print("Trie emoji matching: {} ns/iteration\n", .{ns_per_iteration});
    
    // Performance should be under 1000ns per iteration for typical input
    try testing.expect(ns_per_iteration < 1000);
}
```

### Memory Safety Testing
```zig
test "trie memory safety" {
    const testing = std.testing;
    
    // Test with tracking allocator to detect leaks
    var tracking_allocator = std.testing.LeakCountAllocator.init(testing.allocator);
    defer tracking_allocator.deinit();
    const allocator = tracking_allocator.allocator();
    
    {
        var trie = EmojiTrie.init(allocator);
        defer trie.deinit();
        
        // Add many emojis to stress test memory management
        for (0..1000) |i| {
            const emoji = EmojiSequence{
                .emoji = try allocator.dupe(CodePoint, &[_]CodePoint{@intCast(0x1F300 + i)}),
                .no_fe0f = try allocator.dupe(CodePoint, &[_]CodePoint{@intCast(0x1F300 + i)}),
            };
            try trie.insert(emoji);
        }
        
        // Perform many lookups
        for (0..10000) |i| {
            const lookup = [_]CodePoint{@intCast(0x1F300 + (i % 1000))};
            _ = trie.findLongestMatch(&lookup, 0);
        }
    }
    
    // Verify no memory leaks
    try testing.expect(tracking_allocator.has_leaked == false);
}
```

## Implementation Plan

### Phase 1: Core Trie Implementation
1. Implement `EmojiTrieNode` with basic operations
2. Implement `EmojiTrie` with insert and search
3. Add comprehensive unit tests

### Phase 2: Integration
1. Modify `EmojiMap` to use trie internally
2. Update tokenizer to use new trie-based matching
3. Ensure backward compatibility

### Phase 3: Optimization
1. Add memory pool for trie nodes
2. Optimize FE0F handling
3. Add SIMD optimizations for codepoint comparisons

### Phase 4: Testing & Validation
1. Add fuzz testing suite
2. Performance benchmarking
3. Memory leak detection
4. Validation against Java reference tests

## Migration Strategy

### Backward Compatibility
- Keep existing `EmojiMap` interface unchanged
- Internal implementation switches to trie
- Gradual rollout with feature flags

### Testing Strategy
- Dual implementation testing (hash map vs trie)
- Performance regression testing
- Memory usage monitoring
- Correctness validation against reference

## Performance Expectations

### Expected Improvements
- **Tokenization Speed**: 2-3x improvement on emoji-heavy text
- **Memory Usage**: 20-30% reduction in emoji data storage
- **Scalability**: Linear performance with emoji count increase

### Benchmarking Targets
- Sub-microsecond emoji matching for typical emoji sequences
- Memory usage under 10MB for full emoji dataset
- Zero memory leaks in stress testing

## Error Handling

### Failure Modes
- Out of memory during trie construction
- Corrupted emoji data
- Invalid UTF-8 sequences

### Recovery Strategies
- Graceful degradation to hash map fallback
- Detailed error reporting
- Memory cleanup on failures

## Documentation

### API Documentation
- Comprehensive inline documentation
- Usage examples
- Performance characteristics

### Implementation Notes
- Algorithmic complexity analysis
- Memory layout optimization
- FE0F handling edge cases

This design provides a robust, efficient, and well-tested trie-based emoji matching system that follows the Java reference implementation while leveraging Zig's memory safety features.