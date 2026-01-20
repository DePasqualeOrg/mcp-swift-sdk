#!/bin/bash
# Scan for unused code using Periphery
# Run from the project root directory

set -e

cd "$(dirname "$0")/.."

if ! command -v periphery &> /dev/null; then
    echo "Periphery is not installed. Install with: brew install periphery"
    exit 1
fi

echo "Scanning for unused code..."
periphery scan "$@"
