const std = @import("std");
const ens = @import("ens_normalize");
const tokenizer = ens.tokenizer;
const validator = ens.validator;
const static_data_loader = ens.static_data_loader;
const script_groups = ens.script_groups;
const code_points = ens.code_points;

test "script integration - ASCII label" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create specs
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Create tokenized name
    var tokenized = try tokenizer.TokenizedName.fromInput(allocator, "hello", &specs, false);
    defer tokenized.deinit();
    
    // Validate
    const result = try validator.validateLabel(allocator, tokenized, &specs);
    defer result.deinit();
    
    try testing.expect(result.isASCII());
    try testing.expectEqualStrings("Latin", result.script_group.name);
}

test "script integration - mixed script rejection" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create specs
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Create tokenized name with mixed script (Latin 'a' + Greek 'α')
    var tokenized = try tokenizer.TokenizedName.fromInput(allocator, "aα", &specs, false);
    defer tokenized.deinit();
    
    // Validate - should fail with mixed script
    const result = validator.validateLabel(allocator, tokenized, &specs);
    try testing.expectError(validator.ValidationError.DisallowedCharacter, result);
}

test "script integration - Greek label" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create specs
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Create tokenized name with Greek text
    var tokenized = try tokenizer.TokenizedName.fromInput(allocator, "αβγδε", &specs, false);
    defer tokenized.deinit();
    
    // Validate
    const result = try validator.validateLabel(allocator, tokenized, &specs);
    defer result.deinit();
    
    try testing.expectEqualStrings("Greek", result.script_group.name);
}

test "script integration - Han label" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Create specs
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Create tokenized name with Chinese text
    var tokenized = try tokenizer.TokenizedName.fromInput(allocator, "你好世界", &specs, false);
    defer tokenized.deinit();
    
    // Validate
    const result = try validator.validateLabel(allocator, tokenized, &specs);
    defer result.deinit();
    
    try testing.expectEqualStrings("Han", result.script_group.name);
}

test "script integration - NSM validation" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Load script groups to test NSM
    var groups = try static_data_loader.loadScriptGroups(allocator);
    defer groups.deinit();
    
    // Check that we loaded NSM data
    try testing.expect(groups.nsm_set.count() > 0);
    try testing.expectEqual(@as(u32, 4), groups.nsm_max);
    
    // Test some known NSM characters
    try testing.expect(groups.isNSM(0x0610)); // Arabic sign sallallahou alayhe wassallam
}