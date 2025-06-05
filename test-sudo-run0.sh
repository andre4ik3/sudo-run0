#!/bin/sh

# Test script for sudo-run0 wrapper
# Run this to validate key functionality

echo "Testing sudo-run0 compatibility wrapper..."
echo "=========================================="

# Test 1: Basic functionality
echo "Test 1: Basic privilege escalation"
if ./sudo whoami | grep -q "root"; then
    echo "✓ PASS: Basic sudo functionality works"
else
    echo "✗ FAIL: Basic sudo functionality failed"
fi

# Test 2: Environment variable preservation
echo -e "\nTest 2: Environment variable preservation (-E)"
TEST_VAR="test123"
export TEST_VAR
if ./sudo -E printenv TEST_VAR | grep -q "test123"; then
    echo "✓ PASS: Environment variable preservation works"
else
    echo "✗ FAIL: Environment variable preservation failed"
fi

# Test 3: Specific environment variable preservation
echo -e "\nTest 3: Specific environment variable preservation"
TEST1="value1"
TEST2="value2"
export TEST1 TEST2
if ./sudo --preserve-env=TEST1,TEST2 printenv | grep -q "TEST1=value1" && \
   ./sudo --preserve-env=TEST1,TEST2 printenv | grep -q "TEST2=value2"; then
    echo "✓ PASS: Specific environment variable preservation works"
else
    echo "✗ FAIL: Specific environment variable preservation failed"
fi

# Test 4: Login shell functionality
echo -e "\nTest 4: Login shell functionality (-i)"
shell_output=$(./sudo -i printenv SHELL HOME 2>/dev/null | head -2)
if echo "$shell_output" | grep -q "bash" && echo "$shell_output" | grep -q "/root"; then
    echo "✓ PASS: Login shell sets correct SHELL and HOME"
else
    echo "✗ FAIL: Login shell functionality failed"
fi

# Test 5: User switching
echo -e "\nTest 5: User switching (-u)"
if ./sudo -u root whoami | grep -q "root"; then
    echo "✓ PASS: User switching works"
else
    echo "✗ FAIL: User switching failed"
fi

# Test 6: Help and version
echo -e "\nTest 6: Help and version commands"
if ./sudo --help | grep -q "usage:" && ./sudo --version | grep -q "sudo-run0"; then
    echo "✓ PASS: Help and version commands work"
else
    echo "✗ FAIL: Help and version commands failed"
fi

echo -e "\nAll tests completed!"
echo "Note: Some tests may have triggered authentication prompts above." 
