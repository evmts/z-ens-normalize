#!/bin/bash

# Run specific test file
TEST_FILE=$1
echo "Running test: $TEST_FILE"
ENS_LOG_LEVEL=off zig test "$TEST_FILE" --main-mod-path . -I. --dep ens_normalize -Mens_normalize=src/root.zig 2>&1 | head -100