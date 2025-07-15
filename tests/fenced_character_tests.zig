const std = @import("std");
const tokenizer = @import("../src/tokenizer.zig");
const validator = @import("../src/validator.zig");
const code_points = @import("../src/code_points.zig");
const character_mappings = @import("../src/character_mappings.zig");
const static_data_loader = @import("../src/static_data_loader.zig");

test "fenced characters - leading apostrophe" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test with apostrophe at beginning
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "'hello", &specs, false);
    defer tokenized.deinit();
    
    const result = validator.validateLabel(allocator, tokenized, &specs);
    try testing.expectError(validator.ValidationError.FencedLeading, result);
}

test "fenced characters - trailing apostrophe" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test with apostrophe at end
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello'", &specs, false);
    defer tokenized.deinit();
    
    const result = validator.validateLabel(allocator, tokenized, &specs);
    try testing.expectError(validator.ValidationError.FencedTrailing, result);
}

test "fenced characters - consecutive apostrophes" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test consecutive apostrophes in middle
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hel''lo", &specs, false);
    defer tokenized.deinit();
    
    const result = validator.validateLabel(allocator, tokenized, &specs);
    try testing.expectError(validator.ValidationError.FencedAdjacent, result);
}

test "fenced characters - valid single apostrophe" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test single apostrophe in middle (valid)
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hel'lo", &specs, false);
    defer tokenized.deinit();
    
    const result = try validator.validateLabel(allocator, tokenized, &specs);
    defer result.deinit();
    
    // Should succeed
    try testing.expect(!result.isEmpty());
}

test "fenced characters - hyphen tests" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Valid single hyphen
    {
        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello-world", &specs, false);
        defer tokenized.deinit();
        
        const result = try validator.validateLabel(allocator, tokenized, &specs);
        defer result.deinit();
        
        try testing.expect(!result.isEmpty());
    }
    
    // Invalid consecutive hyphens in middle
    {
        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello--world", &specs, false);
        defer tokenized.deinit();
        
        const result = validator.validateLabel(allocator, tokenized, &specs);
        try testing.expectError(validator.ValidationError.FencedAdjacent, result);
    }
    
    // Valid trailing consecutive hyphens (special case!)
    {
        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello---", &specs, false);
        defer tokenized.deinit();
        
        const result = try validator.validateLabel(allocator, tokenized, &specs);
        defer result.deinit();
        
        // Should succeed - trailing consecutive fenced are allowed
        try testing.expect(!result.isEmpty());
    }
}

test "fenced characters - mixed fenced types" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test consecutive different fenced characters
    const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello'-world", &specs, false);
    defer tokenized.deinit();
    
    const result = validator.validateLabel(allocator, tokenized, &specs);
    try testing.expectError(validator.ValidationError.FencedAdjacent, result);
}

test "fenced characters - colon" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Leading colon
    {
        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, ":hello", &specs, false);
        defer tokenized.deinit();
        
        const result = validator.validateLabel(allocator, tokenized, &specs);
        try testing.expectError(validator.ValidationError.FencedLeading, result);
    }
    
    // Valid colon in middle
    {
        const tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello:world", &specs, false);
        defer tokenized.deinit();
        
        const result = try validator.validateLabel(allocator, tokenized, &specs);
        defer result.deinit();
        
        try testing.expect(!result.isEmpty());
    }
}

test "fenced characters - load from spec.json" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Test loading fenced characters
    var fenced_set = try static_data_loader.loadFencedCharacters(allocator);
    defer fenced_set.deinit();
    
    // Should contain the mapped apostrophe
    try testing.expect(fenced_set.contains(8217)); // Right single quotation mark
    
    // Should contain other fenced characters
    try testing.expect(fenced_set.contains(8260)); // Fraction slash
}