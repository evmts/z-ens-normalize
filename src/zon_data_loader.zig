const std = @import("std");
const character_mappings = @import("character_mappings.zig");
const script_groups = @import("script_groups.zig");
const emoji_mod = @import("emoji.zig");
const nfc = @import("nfc.zig");
const confusables = @import("confusables.zig");
const root = @import("root.zig");
const CodePoint = root.CodePoint;

/// Load character mappings from ZON data (parsed as JSON)
pub fn loadCharacterMappings(allocator: std.mem.Allocator) !character_mappings.CharacterMappings {
    const zon_data = @embedFile("data/spec.zon");
    
    const parsed = try std.json.parseFromSlice(
        std.json.Value, 
        allocator, 
        zon_data, 
        .{ .max_value_len = zon_data.len }
    );
    defer parsed.deinit();
    
    const root_obj = parsed.value.object;
    
    var mappings = try character_mappings.CharacterMappings.init(allocator);
    errdefer mappings.deinit();
    
    // Load mapped characters
    if (root_obj.get("mapped")) |mapped_value| {
        try loadMappedCharacters(&mappings, mapped_value.array.items);
    }
    
    // Load ignored characters
    if (root_obj.get("ignored")) |ignored_value| {
        try loadIgnoredCharacters(&mappings, ignored_value.array.items);
    }
    
    // Load valid characters from groups
    if (root_obj.get("groups")) |groups_value| {
        try loadValidCharactersFromGroups(&mappings, groups_value.array.items);
    }
    
    // Load fenced characters
    if (root_obj.get("fenced")) |fenced_value| {
        try loadFencedCharacters(&mappings, fenced_value.array.items);
    }
    
    return mappings;
}

/// Load script groups from ZON data (parsed as JSON)
pub fn loadScriptGroups(allocator: std.mem.Allocator) !script_groups.ScriptGroups {
    const zon_data = @embedFile("data/spec.zon");
    
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        zon_data,
        .{ .max_value_len = zon_data.len }
    );
    defer parsed.deinit();
    
    const root_obj = parsed.value.object;
    
    // Get groups array
    const groups_array = root_obj.get("groups").?.array.items;
    var groups = script_groups.ScriptGroups.init(allocator);
    groups.groups = try allocator.alloc(script_groups.ScriptGroup, groups_array.len);
    errdefer {
        allocator.free(groups.groups);
        groups.deinit();
    }
    
    // Load each script group
    for (groups_array, 0..) |group_value, i| {
        const group_obj = group_value.object;
        const name = group_obj.get("name").?.string;
        
        var group = script_groups.ScriptGroup.init(allocator, name, i);
        
        // Add primary characters
        if (group_obj.get("primary")) |primary_value| {
            for (primary_value.array.items) |cp_value| {
                try group.addPrimary(@as(CodePoint, @intCast(cp_value.integer)));
            }
        }
        
        // Add secondary characters (if present)
        if (group_obj.get("secondary")) |secondary_value| {
            for (secondary_value.array.items) |cp_value| {
                try group.addSecondary(@as(CodePoint, @intCast(cp_value.integer)));
            }
        }
        
        // Add combining marks (if present)
        if (group_obj.get("cm")) |cm_value| {
            for (cm_value.array.items) |cp_value| {
                try group.addCombiningMark(@as(CodePoint, @intCast(cp_value.integer)));
            }
        }
        
        groups.groups[i] = group;
    }
    
    // Load NSM characters
    if (root_obj.get("nsm")) |nsm_value| {
        for (nsm_value.array.items) |nsm_item| {
            const cp = @as(CodePoint, @intCast(nsm_item.integer));
            try groups.addNSM(cp);
        }
    }
    
    // Load NSM max
    if (root_obj.get("nsm_max")) |nsm_max_value| {
        groups.nsm_max = @as(u32, @intCast(nsm_max_value.integer));
    }
    
    return groups;
}

/// Load NFC data from ZON
pub fn loadNFC(allocator: std.mem.Allocator) !nfc.NFCData {
    const nf_zon_data = @embedFile("data/nf.zon");
    const spec_zon_data = @embedFile("data/spec.zon");
    
    var nfc_data = nfc.NFCData.init(allocator);
    errdefer nfc_data.deinit();
    
    // Load decomposition data from nf.zon
    const nf_parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        nf_zon_data,
        .{ .max_value_len = nf_zon_data.len }
    );
    defer nf_parsed.deinit();
    
    const nf_root_obj = nf_parsed.value.object;
    
    // Load exclusions
    if (nf_root_obj.get("exclusions")) |exclusions_value| {
        for (exclusions_value.array.items) |item| {
            const cp = @as(CodePoint, @intCast(item.integer));
            try nfc_data.exclusions.put(cp, {});
        }
    }
    
    // Load decomposition mappings
    if (nf_root_obj.get("decomp")) |decomp_value| {
        for (decomp_value.array.items) |entry| {
            const entry_array = entry.array.items;
            if (entry_array.len >= 2) {
                const cp = @as(CodePoint, @intCast(entry_array[0].integer));
                var decomp = try allocator.alloc(CodePoint, entry_array.len - 1);
                for (entry_array[1..], 0..) |decomp_item, i| {
                    decomp[i] = @as(CodePoint, @intCast(decomp_item.integer));
                }
                try nfc_data.decomp.put(cp, decomp);
            }
        }
    }
    
    // Load combining class rankings
    if (nf_root_obj.get("ranks")) |ranks_value| {
        for (ranks_value.array.items) |entry| {
            const entry_array = entry.array.items;
            if (entry_array.len >= 2) {
                const cp = @as(CodePoint, @intCast(entry_array[0].integer));
                const rank = @as(u8, @intCast(entry_array[1].integer));
                try nfc_data.ranks.put(cp, rank);
            }
        }
    }
    
    // Load NFC check set from spec.zon
    const spec_parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        spec_zon_data,
        .{ .max_value_len = spec_zon_data.len }
    );
    defer spec_parsed.deinit();
    
    const spec_root_obj = spec_parsed.value.object;
    if (spec_root_obj.get("nfc_check")) |nfc_check_value| {
        for (nfc_check_value.array.items) |item| {
            const cp = @as(CodePoint, @intCast(item.integer));
            try nfc_data.check_set.put(cp, {});
        }
    }
    
    return nfc_data;
}

/// Load emoji data from ZON
pub fn loadEmoji(allocator: std.mem.Allocator) !emoji_mod.EmojiMap {
    const zon_data = @embedFile("data/spec.zon");
    
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        zon_data,
        .{ .max_value_len = zon_data.len }
    );
    defer parsed.deinit();
    
    const root_obj = parsed.value.object;
    
    var emoji_data = emoji_mod.EmojiMap.init(allocator);
    errdefer emoji_data.deinit();
    
    if (root_obj.get("emoji")) |emoji_value| {
        for (emoji_value.array.items) |seq| {
            const seq_array = seq.array.items;
            var cps = try allocator.alloc(CodePoint, seq_array.len);
            for (seq_array, 0..) |cp_value, i| {
                cps[i] = @as(CodePoint, @intCast(cp_value.integer));
            }
            
            // Create EmojiData with both emoji and no_fe0f versions
            const emoji_entry = emoji_mod.EmojiData{
                .emoji = cps,
                .no_fe0f = try allocator.dupe(CodePoint, cps), // For now, same as emoji
            };
            
            try emoji_data.all_emojis.append(emoji_entry);
            
            // Update max length
            if (cps.len > emoji_data.max_length) {
                emoji_data.max_length = cps.len;
            }
        }
    }
    
    return emoji_data;
}

/// Load confusable data from ZON
pub fn loadConfusables(allocator: std.mem.Allocator) !confusables.ConfusableData {
    const zon_data = @embedFile("data/spec.zon");
    
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        allocator,
        zon_data,
        .{ .max_value_len = zon_data.len }
    );
    defer parsed.deinit();
    
    const root_obj = parsed.value.object;
    
    var confusable_data = confusables.ConfusableData.init(allocator);
    errdefer confusable_data.deinit();
    
    if (root_obj.get("wholes")) |wholes_value| {
        const wholes_array = wholes_value.array.items;
        confusable_data.sets = try allocator.alloc(confusables.ConfusableSet, wholes_array.len);
        
        for (wholes_array, 0..) |whole_item, i| {
            const whole_obj = whole_item.object;
            
            // Get target
            const target = if (whole_obj.get("target")) |target_value| 
                try allocator.dupe(u8, target_value.string)
            else 
                try allocator.dupe(u8, "unknown");
            
            var set = confusables.ConfusableSet.init(allocator, target);
            
            // Load valid characters
            if (whole_obj.get("valid")) |valid_value| {
                const valid_array = valid_value.array.items;
                var valid_slice = try allocator.alloc(CodePoint, valid_array.len);
                for (valid_array, 0..) |cp_value, j| {
                    valid_slice[j] = @as(CodePoint, @intCast(cp_value.integer));
                }
                set.valid = valid_slice;
            }
            
            // Load confused characters
            if (whole_obj.get("confused")) |confused_value| {
                const confused_array = confused_value.array.items;
                var confused_slice = try allocator.alloc(CodePoint, confused_array.len);
                for (confused_array, 0..) |cp_value, j| {
                    confused_slice[j] = @as(CodePoint, @intCast(cp_value.integer));
                }
                set.confused = confused_slice;
            }
            
            confusable_data.sets[i] = set;
        }
    }
    
    return confusable_data;
}

// Helper functions (same as original static_data_loader.zig)
fn loadMappedCharacters(mappings: *character_mappings.CharacterMappings, mapped_array: []const std.json.Value) !void {
    for (mapped_array) |item| {
        const item_array = switch (item) {
            .array => |arr| arr.items,
            else => continue,
        };
        
        if (item_array.len < 2) continue;
        
        const from_cp = @as(CodePoint, @intCast(item_array[0].integer));
        
        switch (item_array.len) {
            2 => {
                // Single mapping: [from, to]
                const to_cp = @as(CodePoint, @intCast(item_array[1].integer));
                try mappings.unicode_mappings.put(from_cp, &[_]CodePoint{to_cp});
            },
            else => {
                // Multiple mappings: [from, to1, to2, ...]
                var to_cps = try mappings.allocator.alloc(CodePoint, item_array.len - 1);
                for (item_array[1..], 0..) |to_item, i| {
                    to_cps[i] = @as(CodePoint, @intCast(to_item.integer));
                }
                
                try mappings.unicode_mappings.put(from_cp, to_cps);
            },
        }
    }
}

fn loadIgnoredCharacters(mappings: *character_mappings.CharacterMappings, ignored_array: []const std.json.Value) !void {
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

fn loadValidCharactersFromGroups(mappings: *character_mappings.CharacterMappings, groups_array: []const std.json.Value) !void {
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
        
        // Load secondary valid characters (if present)
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

fn loadFencedCharacters(mappings: *character_mappings.CharacterMappings, fenced_array: []const std.json.Value) !void {
    for (fenced_array) |item| {
        switch (item) {
            .integer => |val| {
                const cp = @as(CodePoint, @intCast(val));
                try mappings.fenced_chars.put(cp, {});
            },
            else => continue,
        }
    }
}

test "ZON data loading" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test character mappings loading
    var mappings = loadCharacterMappings(allocator) catch |err| {
        std.debug.print("Failed to load character mappings: {}\n", .{err});
        return;
    };
    defer mappings.deinit();
    
    try testing.expect(mappings.unicode_mappings.count() > 0);
    try testing.expect(mappings.valid_chars.count() > 0);
    try testing.expect(mappings.ignored_chars.count() > 0);
    try testing.expect(mappings.fenced_chars.count() > 0);

    // Test script groups loading
    var groups = loadScriptGroups(allocator) catch |err| {
        std.debug.print("Failed to load script groups: {}\n", .{err});
        return;
    };
    defer groups.deinit();
    
    try testing.expect(groups.groups.len > 0);
    try testing.expect(groups.nsm_set.count() > 0);
    try testing.expectEqual(@as(usize, 4), groups.nsm_max);
    
    // Test confusables loading
    var confusable_data = loadConfusables(allocator) catch |err| {
        std.debug.print("Failed to load confusables: {}\n", .{err});
        return;
    };
    defer confusable_data.deinit();
    
    try testing.expect(confusable_data.sets.len > 0);
    
    std.debug.print("✓ Successfully loaded ZON data\n", .{});
}