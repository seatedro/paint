#!/usr/bin/env bash

ROOT=$(odin root)
if [ ! $? -eq 0 ]; then
    echo "Your Odin compiler does not have the 'odin root' command, please update or hardcode it in the script."
    exit 1
fi

set -eu

# Figure out the mess that is dynamic libraries.
case $(uname) in
"Darwin")
    case $(uname -m) in
    "arm64") LIB_PATH="macos-arm64" ;;
    *)       LIB_PATH="macos" ;;
    esac

    DLL_EXT=".dylib"
    EXTRA_LINKER_FLAGS="-Wl,-rpath $ROOT/vendor/raylib/$LIB_PATH"
    ;;
*)
    DLL_EXT=".so"
    EXTRA_LINKER_FLAGS="'-Wl,-rpath=\$ORIGIN/linux'"

    # Copy the linux libraries into the project automatically.
    if [ ! -d "linux" ]; then
        mkdir linux
        cp -r $ROOT/vendor/raylib/linux/libraylib*.so* linux
    fi
    ;;
esac

# Build the application.
echo "Building paint$DLL_EXT"
odin build paint -extra-linker-flags:"$EXTRA_LINKER_FLAGS" -define:RAYLIB_SHARED=true -build-mode:dll -out:paint_tmp$DLL_EXT -strict-style -vet -debug

mv paint_tmp$DLL_EXT paint$DLL_EXT

# Do not build the paint_hot_reload.bin if it is already running.
# -f is there to make sure we match against full name, including .bin
if pgrep -f paint_hot_reload.bin > /dev/null; then
    echo "paint running, hot reloading..."
    exit 1
else
    echo "Building paint_hot_reload.bin"
    odin build hot_reload -out:paint_hot_reload.bin -strict-style -vet -debug
fi
