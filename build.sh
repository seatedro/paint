#!/usr/bin/env bash

# Get Odin root directory
ROOT=$(odin root)
if [ ! $? -eq 0 ]; then
    echo "Your Odin compiler does not have the 'odin root' command, please update or hardcode it in the script."
    exit 1
fi

set -eu

# Handle platform-specific settings

# Build the release executable
echo "Building release executable"
odin build . -extra-linker-flags:"-Wl" -out:paint -o:speed -strict-style
