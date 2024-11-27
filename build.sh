#!/bin/bash

# Set error handling
set -e

echo "Starting build process..."

# Create build directory if it doesn't exist
mkdir -p build

# Clean any previous builds
echo "Cleaning previous builds..."
rm -rf build/*
rm -f *.o *.a odingboard

# Set compiler flags
CFLAGS="-Wall -Wextra -fPIC -O2"
INCLUDES="-I/opt/homebrew/include/onnxruntime"

# Detect platform and adjust library paths
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected macOS platform"
    LIBRARY_PATH="/opt/homebrew/lib"
    ONNX_LIB="-L$LIBRARY_PATH -lonnxruntime"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Detected Linux platform"
    LIBRARY_PATH="/usr/local/lib"
    ONNX_LIB="-L$LIBRARY_PATH -lonnxruntime"
else
    echo "Unsupported platform: $OSTYPE"
    exit 1
fi

# Compile the ONNX bridge
echo "Compiling ONNX bridge..."
clang $CFLAGS $INCLUDES \
    -c onnx_bridge.c \
    -o build/onnx_bridge.o

# Compile image utilities
echo "Compiling image utilities..."
clang $CFLAGS $INCLUDES \
    -c image_utils.c \
    -o build/image_utils.o

# Create static library
echo "Creating static library..."
ar rcs build/libonnx_bridge.a build/onnx_bridge.o build/image_utils.o

# Verify the library contents
echo "Verifying library contents..."
ar t build/libonnx_bridge.a

# Build the Odin program
echo "Building Odin program..."
odin build . \
    -extra-linker-flags:"-Lbuild/ -lonnx_bridge $ONNX_LIB" \
    -out:paint

echo "Build complete! Executable is in paint"
echo
echo "Usage:"
echo "  ./paint"
