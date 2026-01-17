#!/bin/bash
set -e

cd "$(dirname "$0")/../../Examples/ConformanceTests"

echo "Building ConformanceServer..."
swift build --product ConformanceServer

echo "Starting ConformanceServer on http://localhost:8080/mcp ..."
swift run ConformanceServer &
SERVER_PID=$!

cleanup() {
    echo "Stopping server (PID $SERVER_PID)..."
    kill $SERVER_PID 2>/dev/null || true
}
trap cleanup EXIT

sleep 2

echo "Running server conformance tests..."
npx @modelcontextprotocol/conformance server --url http://localhost:8080/mcp
