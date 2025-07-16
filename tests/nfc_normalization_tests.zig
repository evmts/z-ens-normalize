const std = @import("std");
const testing = std.testing;
const ens_normalize = @import("ens_normalize");
const tokenizer = ens_normalize.tokenizer;
const validator = ens_normalize.validator;
const code_points = ens_normalize.code_points;

// Test cases for NFC normalization issues
const NFCTestCase = struct {
    name: []const u8,
    input: []const u8,
    expected_normalized: []const u8,
    comment: []const u8,
};

const NFC_TESTS = [_]NFCTestCase{
    // Basic ASCII should not need normalization
    .{
        .name = "ascii_basic",
        .input = "hello",
        .expected_normalized = "hello", 
        .comment = "Basic ASCII should pass through unchanged"
    },
    
    // Case folding should work
    .{
        .name = "uppercase_folding",
        .input = "HELLO",
        .expected_normalized = "hello", 
        .comment = "Uppercase should be folded to lowercase"
    },
    
    // Combining characters need NFC normalization
    .{
        .name = "combining_acute",
        .input = "cafe\u{0301}", // café with combining acute accent
        .expected_normalized = "café", // café with precomposed é
        .comment = "Combining characters should be NFC normalized"
    },
    
    // ENS domain normalization
    .{
        .name = "ens_domain",
        .input = "hello.eth",
        .expected_normalized = "hello.eth", 
        .comment = "Simple ENS domain should normalize successfully"
    },
};

test "NFC normalization - current failures" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    std.debug.print("\n=== NFC NORMALIZATION TEST ===\n", .{});
    
    var failed_tests: usize = 0;
    var total_tests: usize = 0;
    
    for (NFC_TESTS) |test_case| {
        total_tests += 1;
        
        std.debug.print("\nTesting: {s}\n", .{test_case.name});
        std.debug.print("Input: '{s}'\n", .{test_case.input});
        std.debug.print("Expected: '{s}'\n", .{test_case.expected_normalized});
        
        // Try to normalize using our implementation
        const result = ens_normalize.normalize(allocator, test_case.input) catch |err| {
            std.debug.print("❌ {s}: Failed to normalize: {}\n", .{ test_case.name, err });
            failed_tests += 1;
            continue;
        };
        defer allocator.free(result);
        
        std.debug.print("Actual: '{s}'\n", .{result});
        
        if (std.mem.eql(u8, result, test_case.expected_normalized)) {
            std.debug.print("✅ {s}: Passed - {s}\n", .{ test_case.name, test_case.comment });
        } else {
            std.debug.print("❌ {s}: Expected '{s}', got '{s}' - {s}\n", .{ 
                test_case.name, 
                test_case.expected_normalized,
                result,
                test_case.comment 
            });
            failed_tests += 1;
        }
    }
    
    std.debug.print("\n=== RESULTS ===\n", .{});
    std.debug.print("Passed: {}/{}\n", .{ total_tests - failed_tests, total_tests });
    std.debug.print("Failed: {}\n", .{failed_tests});
    
    // This test will initially fail, showing NFC normalization issues
    if (failed_tests > 0) {
        std.debug.print("\n🚨 EXPECTED FAILURES: These show the NFC normalization issues we need to fix!\n", .{});
        return error.ExpectedNFCNormalizationFailures;
    }
}

test "basic ENS normalization - FAILING TEST" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    // This should be a simple case that works
    const input = "hello.eth";
    const result = ens_normalize.normalize(allocator, input) catch |err| {
        std.debug.print("Basic ENS normalization failed: {}\n", .{err});
        std.debug.print("This indicates a fundamental issue in our normalization pipeline\n", .{});
        
        // Let's debug step by step
        std.debug.print("\nDEBUGGING STEPS:\n", .{});
        
        // Step 1: Tokenization
        const specs = code_points.CodePointsSpecs.init(allocator);
        const tokenized = tokenizer.TokenizedName.fromInput(allocator, input, &specs, false) catch |token_err| {
            std.debug.print("1. Tokenization failed: {}\n", .{token_err});
            return error.TokenizationFailed;
        };
        defer tokenized.deinit();
        
        std.debug.print("1. Tokenization succeeded: {} tokens\n", .{tokenized.tokens.len});
        for (tokenized.tokens, 0..) |token, i| {
            std.debug.print("   Token[{}]: {s}\n", .{i, @tagName(token.type)});
        }
        
        // Step 2: Validation  
        const validation_result = validator.validateLabel(allocator, tokenized, &specs) catch |val_err| {
            std.debug.print("2. Validation failed: {}\n", .{val_err});
            return error.ValidationFailed;
        };
        defer validation_result.deinit();
        
        std.debug.print("2. Validation succeeded\n", .{});
        
        return error.NormalizationFailed;
    };
    defer allocator.free(result);
    
    try testing.expectEqualStrings("hello.eth", result);
}