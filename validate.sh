#!/bin/bash
# ENS Normalize Zig - Stage 1 Validation Script
# This script validates that all skeleton code is in place and ready for implementation

set -e  # Exit on first error

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# Helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

section() {
    echo ""
    echo -e "${BLUE}=== $1 ===${NC}"
}

# ============================================================
# File Structure Validation
# ============================================================

section "File Structure Validation"

# Check prompts directory
echo "Checking prompts/ directory..."
PROMPT_COUNT=$(ls -1 prompts/*.md 2>/dev/null | wc -l | tr -d ' ')
echo "Found $PROMPT_COUNT prompt files (expected: 19)"
if [ "$PROMPT_COUNT" -eq 19 ]; then
    pass "All 19 prompts present"
elif [ "$PROMPT_COUNT" -eq 20 ]; then
    warn "20 prompt files found (expected 19, but includes meta guide)"
else
    fail "Expected 19 prompts, found $PROMPT_COUNT"
fi

# Check source directories
echo ""
echo "Checking src/ directories..."
[ -d "src/util" ] && pass "src/util/ exists" || fail "src/util/ missing"
[ -d "src/nf" ] && pass "src/nf/ exists" || fail "src/nf/ missing"
[ -d "src/ensip15" ] && pass "src/ensip15/ exists" || fail "src/ensip15/ missing"

# Check source files
echo ""
echo "Checking source files..."
[ -f "src/util/decoder.zig" ] && pass "decoder.zig exists" || fail "decoder.zig missing"
[ -f "src/util/runeset.zig" ] && pass "runeset.zig exists" || fail "runeset.zig missing"
[ -f "src/nf/nf.zig" ] && pass "nf.zig exists" || fail "nf.zig missing"
[ -f "src/ensip15/types.zig" ] && pass "types.zig exists" || fail "types.zig missing"
[ -f "src/ensip15/errors.zig" ] && pass "errors.zig exists" || fail "errors.zig missing"
[ -f "src/ensip15/ensip15.zig" ] && pass "ensip15.zig exists" || fail "ensip15.zig missing"
[ -f "src/ensip15/utils.zig" ] && pass "utils.zig exists" || fail "utils.zig missing"
[ -f "src/ensip15/init.zig" ] && pass "init.zig exists" || fail "init.zig missing"
[ -f "src/root.zig" ] && pass "root.zig exists" || fail "root.zig missing"

# ============================================================
# Binary File Validation
# ============================================================

section "Binary File Validation"

if [ -f "src/ensip15/spec.bin" ]; then
    SIZE=$(wc -c < "src/ensip15/spec.bin" | tr -d ' ')
    pass "spec.bin exists (${SIZE} bytes)"
    FILE_TYPE=$(file src/ensip15/spec.bin | cut -d: -f2)
    echo "  Type:${FILE_TYPE}"
else
    fail "spec.bin missing"
fi

if [ -f "src/nf/nf.bin" ]; then
    SIZE=$(wc -c < "src/nf/nf.bin" | tr -d ' ')
    pass "nf.bin exists (${SIZE} bytes)"
    FILE_TYPE=$(file src/nf/nf.bin | cut -d: -f2)
    echo "  Type:${FILE_TYPE}"
else
    fail "nf.bin missing"
fi

# ============================================================
# Test Data Validation
# ============================================================

section "Test Data Validation"

if [ -d "test-data" ]; then
    pass "test-data/ directory exists"
else
    warn "test-data/ directory missing (run: zig build copy-test-data)"
fi

if [ -f "test-data/ensip15-tests.json" ]; then
    pass "ensip15-tests.json exists"
    # Validate JSON
    if python3 -m json.tool test-data/ensip15-tests.json > /dev/null 2>&1; then
        pass "  Valid JSON"
    else
        fail "  Invalid JSON"
    fi
else
    warn "ensip15-tests.json missing"
fi

if [ -f "test-data/nf-tests.json" ]; then
    pass "nf-tests.json exists"
    # Validate JSON
    if python3 -m json.tool test-data/nf-tests.json > /dev/null 2>&1; then
        pass "  Valid JSON"
    else
        fail "  Invalid JSON"
    fi
else
    warn "nf-tests.json missing"
fi

# Check test files
echo ""
echo "Checking test files..."
if [ -d "tests" ]; then
    pass "tests/ directory exists"
    [ -f "tests/json_parser.zig" ] && pass "json_parser.zig exists" || warn "json_parser.zig missing"
    [ -f "tests/nf_test.zig" ] && pass "nf_test.zig exists" || warn "nf_test.zig missing"
    [ -f "tests/ensip15_test.zig" ] && pass "ensip15_test.zig exists" || warn "ensip15_test.zig missing"
else
    warn "tests/ directory missing"
fi

# ============================================================
# Build System Validation
# ============================================================

section "Build System Validation"

echo "Running: zig build"
if zig build 2>&1 | tee /tmp/build-output.txt; then
    BUILD_EXIT=$?
    if [ $BUILD_EXIT -eq 0 ]; then
        pass "Build succeeded (exit code: 0)"
    else
        fail "Build failed (exit code: $BUILD_EXIT)"
    fi
else
    BUILD_EXIT=$?
    fail "Build failed (exit code: $BUILD_EXIT)"
fi

# Check for compile errors
COMPILE_ERRORS=$(grep -c "error:" /tmp/build-output.txt 2>/dev/null || echo "0")
COMPILE_ERRORS=$(echo "$COMPILE_ERRORS" | tr -d '\n')
if [ "$COMPILE_ERRORS" -eq 0 ]; then
    pass "No compile errors"
else
    fail "Found $COMPILE_ERRORS compile error(s)"
fi

# ============================================================
# Test Execution Validation
# ============================================================

section "Test Execution Validation"

echo "Running: zig build test"
echo "(Tests are expected to fail with unreachable/panic - this is correct)"
if zig build test 2>&1 | tee /tmp/test-output.txt; then
    TEST_EXIT=$?
else
    TEST_EXIT=$?
fi

# Analyze test output
echo ""
echo "Test Output Analysis:"
PASS_COUNT_TEST=$(grep -c "PASS" /tmp/test-output.txt 2>/dev/null || echo "0")
FAIL_COUNT_TEST=$(grep -c "FAIL" /tmp/test-output.txt 2>/dev/null || echo "0")
PANIC_COUNT=$(grep -c "panic" /tmp/test-output.txt 2>/dev/null || echo "0")
UNREACH_COUNT=$(grep -c "unreachable" /tmp/test-output.txt 2>/dev/null || echo "0")

# Clean up newlines
PASS_COUNT_TEST=$(echo "$PASS_COUNT_TEST" | tr -d '\n')
FAIL_COUNT_TEST=$(echo "$FAIL_COUNT_TEST" | tr -d '\n')
PANIC_COUNT=$(echo "$PANIC_COUNT" | tr -d '\n')
UNREACH_COUNT=$(echo "$UNREACH_COUNT" | tr -d '\n')

echo "  Test passes: $PASS_COUNT_TEST"
echo "  Test failures: $FAIL_COUNT_TEST"
echo "  Panics: $PANIC_COUNT"
echo "  Unreachable: $UNREACH_COUNT"

# At this stage, we expect unit tests in source files to pass
# but integration tests (if any) to fail
if [ $TEST_EXIT -eq 0 ]; then
    pass "All tests passed (unit tests work)"
elif [ $PANIC_COUNT -gt 0 ] || [ $UNREACH_COUNT -gt 0 ]; then
    warn "Tests fail as expected (stubs not implemented)"
else
    warn "Tests failed (exit code: $TEST_EXIT)"
fi

# ============================================================
# Build System Features
# ============================================================

section "Build System Features"

echo "Available build steps:"
zig build --help 2>&1 | grep -A 30 "Steps:" | head -20

# ============================================================
# Code Quality Checks
# ============================================================

section "Code Quality Checks"

# Check for stub patterns
echo "Checking for stub implementations..."
STUB_COUNT=$(grep -r "@panic(\"TODO" src/ 2>/dev/null | wc -l | tr -d ' ')
if [ "$STUB_COUNT" -gt 0 ]; then
    pass "Found $STUB_COUNT TODO stubs (expected at this stage)"
else
    warn "No TODO stubs found (might be fully implemented or missing)"
fi

# Check for documentation comments
echo ""
echo "Checking documentation..."
DOC_COUNT=$(grep -r "^///" src/root.zig 2>/dev/null | wc -l | tr -d ' ')
if [ "$DOC_COUNT" -gt 10 ]; then
    pass "Public API documented ($DOC_COUNT doc comments in root.zig)"
else
    warn "Limited documentation in root.zig ($DOC_COUNT doc comments)"
fi

# ============================================================
# Summary
# ============================================================

section "Validation Summary"

echo ""
echo "Results:"
echo -e "  ${GREEN}Passed:${NC}  $PASS_COUNT"
echo -e "  ${YELLOW}Warnings:${NC} $WARN_COUNT"
echo -e "  ${RED}Failed:${NC}  $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}=== VALIDATION PASSED ===${NC}"
    echo ""
    echo "Stage 1 (skeleton setup) is complete!"
    echo ""
    echo "The project is ready for Stage 2 (implementation)."
    echo ""
    echo "Next steps:"
    echo "  1. Implement decoder functions (src/util/decoder.zig)"
    echo "  2. Implement RuneSet (src/util/runeset.zig)"
    echo "  3. Implement NF normalization (src/nf/nf.zig)"
    echo "  4. Implement ENSIP15 core (src/ensip15/ensip15.zig)"
    echo ""
    exit 0
else
    echo -e "${RED}=== VALIDATION FAILED ===${NC}"
    echo ""
    echo "Please fix the failed checks above before proceeding to Stage 2."
    echo ""
    exit 1
fi

# Cleanup
rm -f /tmp/build-output.txt /tmp/test-output.txt
