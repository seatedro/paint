#!/usr/bin/env bash

# First build and run the hot reload executable
./build_hot.sh

# Watch for changes in any .odin file in the current directory
# --debounce ensures we don't rebuild too frequently
# --clear clears the screen between builds
watchexec \
    --debounce 100 \
    --clear \
    -e odin \
    ./build_hot.sh
