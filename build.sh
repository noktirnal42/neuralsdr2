#!/bin/bash

# NeuralSDR2 Build Script
# Supports both Debug and Release configurations

set -e

PROJECT_NAME="NeuralSDR2"
BUILD_DIR="./build"
CONFIGURATION="${1:-Debug}"

echo "Building $PROJECT_NAME ($CONFIGURATION)..."

# Clean build directory
rm -rf "$BUILD_DIR"

# Create build directory
mkdir -p "$BUILD_DIR"

# Build with Swift Package Manager
swift build -c "$CONFIGURATION"

# Copy executable to build directory
cp ".build/$CONFIGURATION/NeuralSDR2" "$BUILD_DIR/"

echo "Build complete: $BUILD_DIR/NeuralSDR2"
