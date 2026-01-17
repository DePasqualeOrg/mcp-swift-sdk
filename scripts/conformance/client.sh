#!/bin/bash
set -e

cd "$(dirname "$0")/../../Examples/ConformanceTests"

echo "Building ConformanceClient..."
swift build --product ConformanceClient

SCENARIOS=(
    "initialize"
    "tools_call"
    "elicitation-sep1034-client-defaults"
    "sse-retry"
)

PASSED=0
FAILED=0

for scenario in "${SCENARIOS[@]}"; do
    echo ""
    echo "Running scenario: $scenario"
    echo "----------------------------------------"
    if npx @modelcontextprotocol/conformance client \
        --command "swift run ConformanceClient" \
        --scenario "$scenario"; then
        ((PASSED++))
    else
        ((FAILED++))
    fi
done

echo ""
echo "========================================"
echo "Results: $PASSED passed, $FAILED failed"
echo "========================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
