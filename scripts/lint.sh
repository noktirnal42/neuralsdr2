#!/bin/bash
set -e

if command -v swiftlint &> /dev/null; then
    swiftlint lint --config .swiftlint.yml
else
    echo "⚠️ SwiftLint not installed. Install with: brew install swiftlint"
    exit 0
fi
