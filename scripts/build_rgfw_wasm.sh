#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJ_ROOT="$DIR/.."
DEPS_DIR="$PROJ_ROOT/deps/RGFW_wasm"
RGFW_DIR="$DIR/RGFW"

if [ ! -d "$RGFW_DIR" ]; then
    echo "Cloning RGFW..."
    git clone --depth 1 https://github.com/ColleagueRiley/RGFW.git "$RGFW_DIR"
fi

cd "$RGFW_DIR"

echo "Compiling RGFW for WASM (Emscripten)..."
cp RGFW.h RGFW.c
emcc -s ASYNCIFY=1 -O3 -c RGFW.c -D RGFW_IMPLEMENTATION -D RGFW_EXPORT -o RGFW_wasm.o
rm RGFW.c

emar rcs libRGFW_wasm.a RGFW_wasm.o

echo "Copying to deps folder..."
mkdir -p "$DEPS_DIR/lib"
mkdir -p "$DEPS_DIR/include"
cp libRGFW_wasm.a "$DEPS_DIR/lib/"
cp RGFW.h "$DEPS_DIR/include/"

echo "Successfully built RGFW for WASM!"
