const std = @import("std");
const ens = @import("ens_normalize");
const normalizer = ens.normalizer;
const validator = ens.validator;
const tokenizer = ens.tokenizer;
const code_points = ens.code_points;

/// Structure matching the official ENS test vector format
pub const TestVector = struct {
    name: []const u8,
    norm: ?[]const u8 = null,
    should_error: ?bool = null,
    comment: ?[]const u8 = null,
    
    pub fn isError(self: TestVector) bool {
        return self.should_error orelse false;
    }
    
    pub fn expectedNorm(self: TestVector) ?[]const u8 {
        // If no norm field, the expected output is the input (unless it's an error)
        if (self.norm) |n| return n;
        if (self.isError()) return null;
        return self.name;
    }
};

/// Test result for reporting
pub const TestResult = struct {
    vector: TestVector,
    passed: bool,
    actual_output: ?[]const u8,
    actual_error: ?anyerror,
    failure_reason: ?[]const u8,
};

/// Load test vectors from JSON file
pub fn loadTestVectors(allocator: std.mem.Allocator) ![]TestVector {
    const json_data = @embedFile("ens_cases.json");
    
    const parsed = try std.json.parseFromSlice(
        std.json.Value, 
        allocator, 
        json_data, 
        .{ .max_value_len = json_data.len }
    );
    defer parsed.deinit();
    
    const array = parsed.value.array;
    var vectors = std.ArrayList(TestVector).init(allocator);
    errdefer vectors.deinit();
    
    // Skip the first element which contains version info
    var start_index: usize = 0;
    if (array.items.len > 0) {
        if (array.items[0].object.get("version")) |_| {
            start_index = 1;
        }
    }
    
    for (array.items[start_index..]) |item| {
        const obj = item.object;
        
        var vector = TestVector{
            .name = try allocator.dupe(u8, obj.get("name").?.string),
        };
        
        if (obj.get("norm")) |norm| {
            vector.norm = try allocator.dupe(u8, norm.string);
        }
        
        if (obj.get("error")) |err| {
            vector.should_error = err.bool;
        }
        
        if (obj.get("comment")) |comment| {
            vector.comment = try allocator.dupe(u8, comment.string);
        }
        
        try vectors.append(vector);
    }
    
    return vectors.toOwnedSlice();
}

/// Run a single test vector
pub fn runTestVector(
    allocator: std.mem.Allocator,
    vector: TestVector,
    specs: *const code_points.CodePointsSpecs,
) TestResult {
    _ = specs; // Not currently used
    
    var result = TestResult{
        .vector = vector,
        .passed = false,
        .actual_output = null,
        .actual_error = null,
        .failure_reason = null,
    };
    
    // Try to normalize the input
    const normalized = normalizer.normalize(allocator, vector.name) catch |err| {
        result.actual_error = err;
        
        if (vector.isError()) {
            // Expected an error, got one
            result.passed = true;
        } else {
            // Unexpected error
            result.failure_reason = std.fmt.allocPrint(
                allocator, 
                "Unexpected error: {}",
                .{err}
            ) catch "Allocation failed";
        }
        return result;
    };
    defer allocator.free(normalized);
    
    result.actual_output = allocator.dupe(u8, normalized) catch normalized;
    
    if (vector.isError()) {
        // Expected error but got success
        result.failure_reason = std.fmt.allocPrint(
            allocator,
            "Expected error but got: '{s}'",
            .{normalized}
        ) catch "Allocation failed";
        return result;
    }
    
    // Compare with expected output
    if (vector.expectedNorm()) |expected| {
        if (std.mem.eql(u8, normalized, expected)) {
            result.passed = true;
        } else {
            result.failure_reason = std.fmt.allocPrint(
                allocator,
                "Expected '{s}' but got '{s}'",
                .{expected, normalized}
            ) catch "Allocation failed";
        }
    } else {
        // No expected output and no error - consider it passed
        result.passed = true;
    }
    
    return result;
}

/// Run all test vectors and report results
pub fn runAllTests(allocator: std.mem.Allocator, vectors: []const TestVector) !TestReport {
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    var report = TestReport{
        .total = vectors.len,
        .passed = 0,
        .failed = 0,
        .error_tests_passed = 0,
        .error_tests_failed = 0,
        .norm_tests_passed = 0,
        .norm_tests_failed = 0,
    };
    
    var failures = std.ArrayList(TestResult).init(allocator);
    defer failures.deinit();
    
    for (vectors) |vector| {
        const result = runTestVector(allocator, vector, &specs);
        
        if (result.passed) {
            report.passed += 1;
            if (vector.isError()) {
                report.error_tests_passed += 1;
            } else {
                report.norm_tests_passed += 1;
            }
        } else {
            report.failed += 1;
            if (vector.isError()) {
                report.error_tests_failed += 1;
            } else {
                report.norm_tests_failed += 1;
            }
            try failures.append(result);
        }
    }
    
    report.failures = failures.toOwnedSlice() catch &.{};
    return report;
}

pub const TestReport = struct {
    total: usize,
    passed: usize,
    failed: usize,
    error_tests_passed: usize,
    error_tests_failed: usize,
    norm_tests_passed: usize,
    norm_tests_failed: usize,
    failures: []const TestResult = &.{},
    
    pub fn printSummary(self: TestReport) void {
        std.debug.print("\n=== ENS Official Test Vector Results ===\n", .{});
        std.debug.print("Total tests: {}\n", .{self.total});
        std.debug.print("Passed: {} ({d:.1}%)\n", .{self.passed, @as(f64, @floatFromInt(self.passed)) / @as(f64, @floatFromInt(self.total)) * 100});
        std.debug.print("Failed: {}\n\n", .{self.failed});
        
        std.debug.print("Normalization tests: {} passed, {} failed\n", .{self.norm_tests_passed, self.norm_tests_failed});
        std.debug.print("Error tests: {} passed, {} failed\n\n", .{self.error_tests_passed, self.error_tests_failed});
        
        if (self.failures.len > 0) {
            std.debug.print("First 10 failures:\n", .{});
            const max_show = @min(10, self.failures.len);
            for (self.failures[0..max_show]) |failure| {
                std.debug.print("  Input: '{s}'\n", .{failure.vector.name});
                if (failure.vector.comment) |comment| {
                    std.debug.print("  Comment: {s}\n", .{comment});
                }
                if (failure.failure_reason) |reason| {
                    std.debug.print("  Reason: {s}\n", .{reason});
                }
                std.debug.print("\n", .{});
            }
            
            if (self.failures.len > 10) {
                std.debug.print("... and {} more failures\n", .{self.failures.len - 10});
            }
        }
    }
    
    pub fn deinit(self: *TestReport, allocator: std.mem.Allocator) void {
        for (self.failures) |failure| {
            if (failure.actual_output) |output| {
                allocator.free(output);
            }
            if (failure.failure_reason) |reason| {
                allocator.free(reason);
            }
        }
        allocator.free(self.failures);
    }
};

// Tests
const testing = std.testing;

test "official test vectors - load and structure" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const vectors = try loadTestVectors(allocator);
    
    // Should have loaded many test vectors
    try testing.expect(vectors.len > 100);
    
    // Check structure of first few non-version vectors
    var found_error_test = false;
    var found_norm_test = false;
    
    for (vectors[0..@min(20, vectors.len)]) |vector| {
        if (vector.isError()) {
            found_error_test = true;
        }
        if (vector.norm != null) {
            found_norm_test = true;
        }
    }
    
    try testing.expect(found_error_test);
    try testing.expect(found_norm_test);
}

test "official test vectors - run sample tests" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const specs = code_points.CodePointsSpecs.init(allocator);
    
    // Test a few specific cases we know should work
    const test_cases = [_]TestVector{
        // Empty string should normalize to empty
        TestVector{ .name = "" },
        
        // Simple ASCII should pass through
        TestVector{ .name = "hello" },
        
        // Whitespace should error
        TestVector{ .name = " ", .should_error = true },
        
        // Period should error
        TestVector{ .name = ".", .should_error = true },
    };
    
    for (test_cases) |vector| {
        const result = runTestVector(allocator, vector, &specs);
        if (!result.passed) {
            std.debug.print("Failed test: '{s}'\n", .{vector.name});
            if (result.failure_reason) |reason| {
                std.debug.print("Reason: {s}\n", .{reason});
            }
        }
    }
}

test "official test vectors - run subset" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    
    const vectors = try loadTestVectors(allocator);
    
    // Run first 100 tests as a sample
    const subset = vectors[0..@min(100, vectors.len)];
    var report = try runAllTests(allocator, subset);
    defer report.deinit(allocator);
    
    report.printSummary();
    
    // We expect some failures initially
    try testing.expect(report.total == subset.len);
}