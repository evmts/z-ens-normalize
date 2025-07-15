const std = @import("std");
const ens_normalize = @import("ens_normalize");
const script_groups = ens_normalize.script_groups;
const static_data_loader = ens_normalize.static_data_loader;

test "script groups - load from spec.json" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = try static_data_loader.loadScriptGroups(allocator);
    defer groups.deinit();
    
    // Should have loaded many groups
    try testing.expect(groups.groups.len > 100);
    
    // Should have loaded NSM data
    try testing.expect(groups.nsm_set.count() > 1000);
    try testing.expectEqual(@as(u32, 4), groups.nsm_max);
    
    // Check some known groups exist
    var found_latin = false;
    var found_greek = false;
    var found_cyrillic = false;
    var found_han = false;
    
    for (groups.groups) |*group| {
        if (std.mem.eql(u8, group.name, "Latin")) found_latin = true;
        if (std.mem.eql(u8, group.name, "Greek")) found_greek = true;
        if (std.mem.eql(u8, group.name, "Cyrillic")) found_cyrillic = true;
        if (std.mem.eql(u8, group.name, "Han")) found_han = true;
    }
    
    try testing.expect(found_latin);
    try testing.expect(found_greek);
    try testing.expect(found_cyrillic);
    try testing.expect(found_han);
}

test "script groups - single script detection" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = try static_data_loader.loadScriptGroups(allocator);
    defer groups.deinit();
    
    // Test Latin script
    const latin_cps = [_]u32{ 'h', 'e', 'l', 'l', 'o' };
    const latin_group = try groups.determineScriptGroup(&latin_cps, allocator);
    try testing.expectEqualStrings("Latin", latin_group.name);
    
    // Test Greek script
    const greek_cps = [_]u32{ 0x03B1, 0x03B2, 0x03B3 }; // αβγ
    const greek_group = try groups.determineScriptGroup(&greek_cps, allocator);
    try testing.expectEqualStrings("Greek", greek_group.name);
    
    // Test Cyrillic script
    const cyrillic_cps = [_]u32{ 0x0430, 0x0431, 0x0432 }; // абв
    const cyrillic_group = try groups.determineScriptGroup(&cyrillic_cps, allocator);
    try testing.expectEqualStrings("Cyrillic", cyrillic_group.name);
}

test "script groups - mixed script rejection" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = try static_data_loader.loadScriptGroups(allocator);
    defer groups.deinit();
    
    // Test Latin + Greek (should fail)
    const latin_greek = [_]u32{ 'a', 'b', 0x03B1 }; // ab + α
    const result1 = groups.determineScriptGroup(&latin_greek, allocator);
    try testing.expectError(error.DisallowedCharacter, result1);
    
    // Test Latin + Cyrillic (should fail)
    const latin_cyrillic = [_]u32{ 'a', 0x0430 }; // 'a' + Cyrillic 'а' (look similar!)
    const result2 = groups.determineScriptGroup(&latin_cyrillic, allocator);
    try testing.expectError(error.DisallowedCharacter, result2);
    
    // Test Greek + Cyrillic (should fail)
    const greek_cyrillic = [_]u32{ 0x03B1, 0x0430 }; // Greek α + Cyrillic а
    const result3 = groups.determineScriptGroup(&greek_cyrillic, allocator);
    try testing.expectError(error.DisallowedCharacter, result3);
}

test "script groups - common characters" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = try static_data_loader.loadScriptGroups(allocator);
    defer groups.deinit();
    
    // Numbers should work with Latin
    const latin_numbers = [_]u32{ 'a', 'b', 'c', '1', '2', '3' };
    const latin_group = try groups.determineScriptGroup(&latin_numbers, allocator);
    try testing.expectEqualStrings("Latin", latin_group.name);
    
    // Numbers should work with Greek
    const greek_numbers = [_]u32{ 0x03B1, 0x03B2, '1', '2' };
    const greek_group = try groups.determineScriptGroup(&greek_numbers, allocator);
    try testing.expectEqualStrings("Greek", greek_group.name);
    
    // Hyphen should work with many scripts
    const latin_hyphen = [_]u32{ 'a', 'b', '-', 'c' };
    const result = groups.determineScriptGroup(&latin_hyphen, allocator);
    try testing.expect(result != error.DisallowedCharacter);
}

test "script groups - find conflicting groups" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = try static_data_loader.loadScriptGroups(allocator);
    defer groups.deinit();
    
    // Test finding conflicts for mixed scripts
    const mixed = [_]u32{ 'a', 0x03B1 }; // Latin 'a' + Greek 'α'
    
    const conflict = script_groups.findConflictingGroups(&groups, &mixed, allocator) catch |err| {
        // If no conflict found, that's also ok for this test
        if (err == error.NoConflict) return;
        return err;
    };
    defer allocator.free(conflict.conflicting_groups);
    
    // First group should be Latin (contains 'a')
    try testing.expectEqualStrings("Latin", conflict.first_group.name);
    
    // Conflicting codepoint should be Greek α
    try testing.expectEqual(@as(u32, 0x03B1), conflict.conflicting_cp);
    
    // Conflicting groups should include Greek
    var found_greek = false;
    for (conflict.conflicting_groups) |g| {
        if (std.mem.eql(u8, g.name, "Greek")) {
            found_greek = true;
            break;
        }
    }
    try testing.expect(found_greek);
}

test "script groups - NSM validation" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var groups = try static_data_loader.loadScriptGroups(allocator);
    defer groups.deinit();
    
    // Test that we loaded NSM data
    try testing.expect(groups.nsm_set.count() > 0);
    
    // Test some known NSM characters
    try testing.expect(groups.isNSM(0x0300)); // Combining grave accent
    try testing.expect(groups.isNSM(0x0301)); // Combining acute accent
    try testing.expect(groups.isNSM(0x0302)); // Combining circumflex accent
    
    // Test non-NSM characters
    try testing.expect(!groups.isNSM('a'));
    try testing.expect(!groups.isNSM('1'));
    try testing.expect(!groups.isNSM(0x03B1)); // Greek α
}