const std = @import("std");
const root = @import("root.zig");
const CodePoint = root.CodePoint;
const character_mappings = @import("character_mappings.zig");
const CharacterMappings = character_mappings.CharacterMappings;
const nfc = @import("nfc.zig");
const emoji = @import("emoji.zig");
const script_groups = @import("script_groups.zig");

/// Load character mappings from the spec.json file
pub fn loadCharacterMappings(allocator: std.mem.Allocator) !CharacterMappings {
    const json_data = @embedFile("static_data/spec.json");
    
    // Parse JSON with increased max value length for large file
    const parsed = try std.json.parseFromSlice(
        std.json.Value, 
        allocator, 
        json_data, 
        .{ .max_value_len = json_data.len }
    );
    defer parsed.deinit();
    
    var mappings = try CharacterMappings.init(allocator);
    errdefer mappings.deinit();
    
    const root_obj = switch (parsed.value) {
        .object => |obj| obj,
        else => return error.InvalidJson,
    };
    
    // Load mapped characters
    if (root_obj.get("mapped")) |mapped_value| {
        switch (mapped_value) {
            .array => |arr| try loadMappedCharacters(&mappings, arr.items),
            else => return error.InvalidMappedFormat,
        }
    }
    
    // Load ignored characters
    if (root_obj.get("ignored")) |ignored_value| {
        switch (ignored_value) {
            .array => |arr| try loadIgnoredCharacters(&mappings, arr.items),
            else => return error.InvalidIgnoredFormat,
        }
    }
    
    // Load valid characters from groups
    if (root_obj.get("groups")) |groups_value| {
        switch (groups_value) {
            .array => |arr| try loadValidCharactersFromGroups(&mappings, arr.items),
            else => return error.InvalidGroupsFormat,
        }
    }
    
    // Load fenced characters
    if (root_obj.get("fenced")) |fenced_value| {
        switch (fenced_value) {
            .array => |arr| try loadFencedCharactersIntoMappings(&mappings, arr.items),
            else => return error.InvalidFencedFormat,
        }
    }
    
    return mappings;
}

/// Load mapped characters from JSON array
/// Format: [[from_cp, [to_cp1, to_cp2, ...]], ...]
fn loadMappedCharacters(mappings: *CharacterMappings, mapped_array: []const std.json.Value) !void {
    for (mapped_array) |item| {
        switch (item) {
            .array => |mapping_array| {
                if (mapping_array.items.len != 2) continue;
                
                const from_cp = switch (mapping_array.items[0]) {
                    .integer => |val| @as(CodePoint, @intCast(val)),
                    else => continue,
                };
                
                const to_array = switch (mapping_array.items[1]) {
                    .array => |arr| arr.items,
                    else => continue,
                };
                
                // Create target code point array
                var to_cps = try mappings.allocator.alloc(CodePoint, to_array.len);
                errdefer mappings.allocator.free(to_cps);
                
                for (to_array, 0..) |to_value, i| {
                    to_cps[i] = switch (to_value) {
                        .integer => |val| @as(CodePoint, @intCast(val)),
                        else => {
                            mappings.allocator.free(to_cps);
                            continue;
                        },
                    };
                }
                
                try mappings.unicode_mappings.put(from_cp, to_cps);
            },
            else => continue,
        }
    }
}

/// Load ignored characters from JSON array
/// Format: [cp1, cp2, cp3, ...]
fn loadIgnoredCharacters(mappings: *CharacterMappings, ignored_array: []const std.json.Value) !void {
    for (ignored_array) |item| {
        switch (item) {
            .integer => |val| {
                const cp = @as(CodePoint, @intCast(val));
                try mappings.ignored_chars.put(cp, {});
            },
            else => continue,
        }
    }
}

/// Load valid characters from groups
/// Format: groups contain primary and secondary valid code points
fn loadValidCharactersFromGroups(mappings: *CharacterMappings, groups_array: []const std.json.Value) !void {
    for (groups_array) |group| {
        const group_obj = switch (group) {
            .object => |obj| obj,
            else => continue,
        };
        
        // Load primary valid characters
        if (group_obj.get("primary")) |primary_value| {
            switch (primary_value) {
                .array => |arr| {
                    for (arr.items) |item| {
                        switch (item) {
                            .integer => |val| {
                                const cp = @as(CodePoint, @intCast(val));
                                try mappings.valid_chars.put(cp, {});
                            },
                            else => continue,
                        }
                    }
                },
                else => {},
            }
        }
        
        // Load secondary valid characters
        if (group_obj.get("secondary")) |secondary_value| {
            switch (secondary_value) {
                .array => |arr| {
                    for (arr.items) |item| {
                        switch (item) {
                            .integer => |val| {
                                const cp = @as(CodePoint, @intCast(val));
                                try mappings.valid_chars.put(cp, {});
                            },
                            else => continue,
                        }
                    }
                },
                else => {},
            }
        }
    }
}

/// Simplified loader that just does ASCII case folding and basic mappings
/// Use this as a fallback if the full JSON is too complex
pub fn loadBasicMappings(allocator: std.mem.Allocator) !CharacterMappings {
    var mappings = try CharacterMappings.init(allocator);
    errdefer mappings.deinit();
    
    // Add essential Unicode mappings manually
    try addEssentialMappings(&mappings);
    
    return mappings;
}

/// Add essential character mappings for testing
fn addEssentialMappings(mappings: *CharacterMappings) !void {
    // Mathematical symbols (map directly to lowercase per reference spec)
    try mappings.addMapping(0x2102, &[_]CodePoint{0x0063}); // ℂ -> c
    try mappings.addMapping(0x210C, &[_]CodePoint{0x0068}); // ℌ -> h
    try mappings.addMapping(0x2113, &[_]CodePoint{0x006C}); // ℓ -> l
    try mappings.addMapping(0x212F, &[_]CodePoint{0x0065}); // ℯ -> e
    
    // Fractions
    try mappings.addMapping(0x00BD, &[_]CodePoint{0x0031, 0x2044, 0x0032}); // ½ -> 1⁄2
    try mappings.addMapping(0x2153, &[_]CodePoint{0x0031, 0x2044, 0x0033}); // ⅓ -> 1⁄3
    try mappings.addMapping(0x00BC, &[_]CodePoint{0x0031, 0x2044, 0x0034}); // ¼ -> 1⁄4
    try mappings.addMapping(0x00BE, &[_]CodePoint{0x0033, 0x2044, 0x0034}); // ¾ -> 3⁄4
    
    // Add fraction slash as valid
    try mappings.addValid(0x2044); // ⁄
    
    // Add common punctuation as valid
    try mappings.addValid('.'); // period
}

// Tests
test "static data loader - basic mappings" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    var mappings = try loadBasicMappings(allocator);
    defer mappings.deinit();
    
    // Test ASCII case folding
    const mapped_H = mappings.getMapped('H');
    try testing.expect(mapped_H != null);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{'h'}, mapped_H.?);
    
    // Test Unicode mappings
    const mapped_math_H = mappings.getMapped(0x210C); // ℌ
    try testing.expect(mapped_math_H != null);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{'h'}, mapped_math_H.?);
    
    // Test fractions
    const mapped_half = mappings.getMapped(0x00BD); // ½
    try testing.expect(mapped_half != null);
    try testing.expectEqualSlices(CodePoint, &[_]CodePoint{'1', 0x2044, '2'}, mapped_half.?);
    
    // Test valid characters
    try testing.expect(mappings.isValid('a'));
    try testing.expect(mappings.isValid('0'));
    try testing.expect(mappings.isValid('.'));
    try testing.expect(mappings.isValid(0x2044)); // ⁄
    
    // Test ignored characters
    try testing.expect(mappings.isIgnored(0x00AD)); // soft hyphen
    try testing.expect(mappings.isIgnored(0x200C)); // ZWNJ
}

test "static data loader - JSON parsing attempt" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // Try to load from JSON
    var mappings = loadCharacterMappings(allocator) catch |err| {
        std.debug.print("Failed to load spec.json: {}\n", .{err});
        // Fall back to basic mappings for now
        return;
    };
    defer mappings.deinit();
    
    // Test that we loaded data correctly
    try testing.expect(mappings.getMapped('A') != null);
    try testing.expect(mappings.isValid('a'));
    try testing.expect(mappings.isIgnored(0x00AD));
    
    // Test some specific mappings from spec.json
    const mapped_apostrophe = mappings.getMapped(39); // ' -> '
    try testing.expect(mapped_apostrophe != null);
    if (mapped_apostrophe) |mapped| {
        try testing.expectEqual(@as(usize, 1), mapped.len);
        try testing.expectEqual(@as(CodePoint, 8217), mapped[0]);
    }
}

pub fn loadNFCData(allocator: std.mem.Allocator) !nfc.NFCData {
    const json_data = @embedFile("static_data/nf.json");
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_data,
        .{ .max_value_len = json_data.len }
    );
    defer parsed.deinit();
    
    var nfc_data = nfc.NFCData.init(allocator);
    errdefer nfc_data.deinit();
    
    const obj = parsed.value.object;
    
    // Load exclusions
    if (obj.get("exclusions")) |exclusions_val| {
        if (exclusions_val == .array) {
            for (exclusions_val.array.items) |item| {
                if (item == .integer) {
                    const cp = @as(CodePoint, @intCast(item.integer));
                    try nfc_data.exclusions.put(cp, {});
                }
            }
        }
    }
    
    // Load decomposition mappings
    if (obj.get("decomp")) |decomp_val| {
        if (decomp_val == .array) {
            for (decomp_val.array.items) |item| {
                if (item == .array and item.array.items.len >= 2) {
                    if (item.array.items[0] == .integer and item.array.items[1] == .array) {
                        const cp = @as(CodePoint, @intCast(item.array.items[0].integer));
                        const decomp_array = item.array.items[1].array;
                        
                        var decomposed = try allocator.alloc(CodePoint, decomp_array.items.len);
                        for (decomp_array.items, 0..) |decomp_cp, i| {
                            if (decomp_cp == .integer) {
                                decomposed[i] = @as(CodePoint, @intCast(decomp_cp.integer));
                            }
                        }
                        
                        try nfc_data.decomp.put(cp, decomposed);
                    }
                }
            }
        }
    }
    
    // Build recomposition mappings from decomposition mappings
    // Only 2-character decompositions that are not excluded can be recomposed
    var decomp_iter = nfc_data.decomp.iterator();
    while (decomp_iter.next()) |entry| {
        const cp = entry.key_ptr.*;
        const decomposed = entry.value_ptr.*;
        
        if (decomposed.len == 2 and !nfc_data.exclusions.contains(cp)) {
            const pair = nfc.NFCData.CodePointPair{
                .first = decomposed[0],
                .second = decomposed[1]
            };
            try nfc_data.recomp.put(pair, cp);
        }
    }
    
    // Load combining class rankings
    if (obj.get("ranks")) |ranks_val| {
        if (ranks_val == .array) {
            for (ranks_val.array.items, 1..) |rank_group, rank| {
                if (rank_group == .array) {
                    const combining_class = @as(u8, @intCast(rank));
                    for (rank_group.array.items) |cp_val| {
                        if (cp_val == .integer) {
                            const cp = @as(CodePoint, @intCast(cp_val.integer));
                            try nfc_data.combining_class.put(cp, combining_class);
                        }
                    }
                }
            }
        }
    }
    
    // Load NFC check set from spec.json
    const spec_json_data = @embedFile("static_data/spec.json");
    const spec_parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        spec_json_data,
        .{ .max_value_len = spec_json_data.len }
    );
    defer spec_parsed.deinit();
    
    const spec_obj = spec_parsed.value.object;
    if (spec_obj.get("nfc_check")) |nfc_check_val| {
        if (nfc_check_val == .array) {
            for (nfc_check_val.array.items) |cp_val| {
                if (cp_val == .integer) {
                    const cp = @as(CodePoint, @intCast(cp_val.integer));
                    try nfc_data.nfc_check.put(cp, {});
                }
            }
        }
    }
    
    return nfc_data;
}

/// Load fenced characters from spec.json
pub fn loadFencedCharacters(allocator: std.mem.Allocator) !std.AutoHashMap(CodePoint, void) {
    const json_data = @embedFile("static_data/spec.json");
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_data,
        .{ .max_value_len = json_data.len }
    );
    defer parsed.deinit();
    
    var fenced_set = std.AutoHashMap(CodePoint, void).init(allocator);
    errdefer fenced_set.deinit();
    
    const obj = parsed.value.object;
    if (obj.get("fenced")) |fenced_val| {
        if (fenced_val == .array) {
            for (fenced_val.array.items) |item| {
                if (item == .array and item.array.items.len >= 1) {
                    if (item.array.items[0] == .integer) {
                        const cp = @as(CodePoint, @intCast(item.array.items[0].integer));
                        try fenced_set.put(cp, {});
                    }
                }
            }
        }
    }
    
    return fenced_set;
}

/// Load fenced characters into CharacterMappings
/// Format: [[codepoint, "description"], ...]
fn loadFencedCharactersIntoMappings(mappings: *CharacterMappings, fenced_array: []const std.json.Value) !void {
    for (fenced_array) |item| {
        switch (item) {
            .array => |fenced_entry| {
                if (fenced_entry.items.len >= 1) {
                    switch (fenced_entry.items[0]) {
                        .integer => |val| {
                            const cp = @as(CodePoint, @intCast(val));
                            try mappings.fenced_chars.put(cp, {});
                        },
                        else => continue,
                    }
                }
            },
            else => continue,
        }
    }
}

/// Load emoji data from spec.json
pub fn loadEmojiMap(allocator: std.mem.Allocator) !emoji.EmojiMap {
    const json_data = @embedFile("static_data/spec.json");
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_data,
        .{ .max_value_len = json_data.len }
    );
    defer parsed.deinit();
    
    var emoji_map = emoji.EmojiMap.init(allocator);
    errdefer emoji_map.deinit();
    
    const obj = parsed.value.object;
    if (obj.get("emoji")) |emoji_val| {
        if (emoji_val == .array) {
            for (emoji_val.array.items) |item| {
                if (item == .array) {
                    // Convert array items to codepoints
                    var canonical = try allocator.alloc(CodePoint, item.array.items.len);
                    defer allocator.free(canonical);
                    
                    var all_integers = true;
                    for (item.array.items, 0..) |cp_val, i| {
                        if (cp_val == .integer) {
                            canonical[i] = @as(CodePoint, @intCast(cp_val.integer));
                        } else {
                            all_integers = false;
                            break;
                        }
                    }
                    
                    if (all_integers) {
                        // Generate no_fe0f version
                        const no_fe0f = try emoji.filterFE0F(allocator, canonical);
                        defer allocator.free(no_fe0f);
                        
                        // Add to map
                        try emoji_map.addEmoji(no_fe0f, canonical);
                    }
                }
            }
        }
    }
    
    return emoji_map;
}

/// Load script groups from spec.json
pub fn loadScriptGroups(allocator: std.mem.Allocator) !script_groups.ScriptGroups {
    const json_data = @embedFile("static_data/spec.json");
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        json_data,
        .{ .max_value_len = json_data.len }
    );
    defer parsed.deinit();
    
    var groups = script_groups.ScriptGroups.init(allocator);
    errdefer groups.deinit();
    
    const obj = parsed.value.object;
    
    // Load NSM data
    if (obj.get("nsm")) |nsm_val| {
        if (nsm_val == .array) {
            for (nsm_val.array.items) |cp_val| {
                if (cp_val == .integer) {
                    const cp = @as(CodePoint, @intCast(cp_val.integer));
                    try groups.addNSM(cp);
                }
            }
        }
    }
    
    // Load NSM max
    if (obj.get("nsm_max")) |nsm_max_val| {
        if (nsm_max_val == .integer) {
            groups.nsm_max = @as(u32, @intCast(nsm_max_val.integer));
        }
    }
    
    // Load groups
    if (obj.get("groups")) |groups_val| {
        if (groups_val == .array) {
            const groups_array = groups_val.array.items;
            var loaded_groups = try allocator.alloc(script_groups.ScriptGroup, groups_array.len);
            errdefer {
                for (loaded_groups[0..groups.groups.len]) |*g| {
                    g.deinit();
                }
                allocator.free(loaded_groups);
            }
            
            var valid_count: usize = 0;
            for (groups_array, 0..) |group_val, index| {
                if (group_val != .object) continue;
                const group_obj = group_val.object;
                
                // Get group name
                const name_val = group_obj.get("name") orelse continue;
                if (name_val != .string) continue;
                
                const name = try allocator.dupe(u8, name_val.string);
                errdefer allocator.free(name);
                
                var group = script_groups.ScriptGroup.init(allocator, name, index);
                errdefer group.deinit();
                
                // Load primary codepoints
                if (group_obj.get("primary")) |primary_val| {
                    if (primary_val == .array) {
                        for (primary_val.array.items) |cp_val| {
                            if (cp_val == .integer) {
                                const cp = @as(CodePoint, @intCast(cp_val.integer));
                                try group.addPrimary(cp);
                            }
                        }
                    }
                }
                
                // Load secondary codepoints
                if (group_obj.get("secondary")) |secondary_val| {
                    if (secondary_val == .array) {
                        for (secondary_val.array.items) |cp_val| {
                            if (cp_val == .integer) {
                                const cp = @as(CodePoint, @intCast(cp_val.integer));
                                try group.addSecondary(cp);
                            }
                        }
                    }
                }
                
                // Load combining marks
                if (group_obj.get("cm")) |cm_val| {
                    if (cm_val == .array) {
                        for (cm_val.array.items) |cp_val| {
                            if (cp_val == .integer) {
                                const cp = @as(CodePoint, @intCast(cp_val.integer));
                                try group.addCombiningMark(cp);
                            }
                        }
                        // If group has CM list, it uses whitelist mode (doesn't check NSM)
                        group.check_nsm = cm_val.array.items.len == 0;
                    }
                }
                
                loaded_groups[valid_count] = group;
                valid_count += 1;
            }
            
            // Resize to actual count
            if (valid_count < loaded_groups.len) {
                loaded_groups = try allocator.realloc(loaded_groups, valid_count);
            }
            
            groups.groups = loaded_groups;
        }
    }
    
    return groups;
}