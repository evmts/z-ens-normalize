const std = @import("std");
const testing = std.testing;
const root = @import("ens_normalize");
const normalizer = root.normalizer;
const tokenizer = root.tokenizer;
const validate = root.validate;
const log = @import("ens_normalize").logger;

test "single label name without dots" {
    log.setLogLevel(.err); // Reduce noise in tests
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    const input = "hello";
    const processed = try ens.process(input);
    defer processed.deinit();
    
    // Should have exactly 1 label
    try testing.expectEqual(@as(usize, 1), processed.labels.len);
    try testing.expectEqual(validate.LabelType.ascii, processed.labels[0].label_type);
}

test "multi-label name with single dot" {
    log.setLogLevel(.err); // Reduce noise in tests
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    const input = "hello.eth";
    const processed = try ens.process(input);
    defer processed.deinit();
    
    // Should have exactly 2 labels
    try testing.expectEqual(@as(usize, 2), processed.labels.len);
    try testing.expectEqual(validate.LabelType.ascii, processed.labels[0].label_type);
    try testing.expectEqual(validate.LabelType.ascii, processed.labels[1].label_type);
}

test "multi-label name with multiple dots" {
    log.setLogLevel(.err); // Reduce noise in tests
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    const input = "sub.domain.eth";
    const processed = try ens.process(input);
    defer processed.deinit();
    
    // Should have exactly 3 labels
    try testing.expectEqual(@as(usize, 3), processed.labels.len);
    try testing.expectEqual(validate.LabelType.ascii, processed.labels[0].label_type);
    try testing.expectEqual(validate.LabelType.ascii, processed.labels[1].label_type);
    try testing.expectEqual(validate.LabelType.ascii, processed.labels[2].label_type);
}

test "empty label between dots should fail" {
    log.setLogLevel(.err); // Reduce noise in tests
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    const input = "hello..eth";
    const result = ens.process(input);
    try testing.expectError(root.error_types.ProcessError.DisallowedSequence, result);
}

test "leading dot should fail" {
    log.setLogLevel(.err); // Reduce noise in tests
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    const input = ".hello";
    const result = ens.process(input);
    try testing.expectError(root.error_types.ProcessError.DisallowedSequence, result);
}

test "trailing dot should fail" {
    log.setLogLevel(.err); // Reduce noise in tests
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    const input = "hello.";
    const result = ens.process(input);
    try testing.expectError(root.error_types.ProcessError.DisallowedSequence, result);
}

test "dots in normalized output" {
    log.setLogLevel(.err); // Reduce noise in tests
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    const input = "hello.world.eth";
    const normalized = try ens.normalize(input);
    defer allocator.free(normalized);
    
    // Should preserve dots in output
    try testing.expectEqualStrings("hello.world.eth", normalized);
}

test "emoji and text labels separated by dots" {
    log.setLogLevel(.err); // Reduce noise in tests
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    const input = "👍.hello.eth";
    const processed = try ens.process(input);
    defer processed.deinit();
    
    // Should have 3 labels
    try testing.expectEqual(@as(usize, 3), processed.labels.len);
    try testing.expectEqual(validate.LabelType.emoji, processed.labels[0].label_type);
    try testing.expectEqual(validate.LabelType.ascii, processed.labels[1].label_type);
    try testing.expectEqual(validate.LabelType.ascii, processed.labels[2].label_type);
}

test "unicode labels separated by dots" {
    log.setLogLevel(.err); // Reduce noise in tests
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    const input = "café.münchen.eth";
    const processed = try ens.process(input);
    defer processed.deinit();
    
    // Should have 3 labels
    try testing.expectEqual(@as(usize, 3), processed.labels.len);
    // These will be "other" type since we haven't implemented script detection yet
    try testing.expect(processed.labels[0].label_type == .other);
    try testing.expect(processed.labels[1].label_type == .other);
    try testing.expectEqual(validate.LabelType.ascii, processed.labels[2].label_type);
}

test "tokenization preserves stop tokens" {
    log.setLogLevel(.err); // Reduce noise in tests
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var ens = try normalizer.EnsNameNormalizer.init(allocator);
    defer ens.deinit();
    
    const input = "hello.world";
    const tokenized = try ens.tokenize(input);
    defer tokenized.deinit();
    
    // Count stop tokens
    var stop_count: usize = 0;
    for (tokenized.tokens) |token| {
        if (token.type == .stop) {
            stop_count += 1;
        }
    }
    
    try testing.expectEqual(@as(usize, 1), stop_count);
}