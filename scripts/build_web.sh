#!/bin/bash
set -e

echo "Building Asteroids for Web..."

echo "Compiling object files..."
OBJ_DIR="build/obj/wasm32"
rm -rf "$OBJ_DIR"
c3c build web_objs

echo "Linking..."
DEPS_DIR="deps"
OUTPUT_DIR="build"
OBJS=$(find "$OBJ_DIR" -name "*.wasm")

emcc $OBJS \
    "$DEPS_DIR/RGFW_wasm/lib/libRGFW_wasm.a" \
    "$DEPS_DIR/miniaudio_wasm/lib/libminiaudio.a" \
    -o "$OUTPUT_DIR/index.html" \
    --shell-file lib/shell.html \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s STACK_SIZE=4194304 \
    -s "EXPORTED_RUNTIME_METHODS=['requestFullscreen', 'HEAPU8']" \
    -s "EXPORTED_FUNCTIONS=['_main', '_wasm_start_game', '_web_tick', '_malloc', '_free']" \
    -s "DEFAULT_LIBRARY_FUNCS_TO_INCLUDE=['\$stringToNewUTF8']" \
    -O2

#stringToNewUTF8 comes from RGFW

# for debugguing
#    -s SAFE_HEAP=1 \
#    -s STACK_OVERFLOW_CHECK=2 \
#    -g3 \
#    -s ASSERTIONS=2 \
#    -O0

#    -s INITIAL_MEMORY=33554432 \
#    -s ERROR_ON_UNDEFINED_SYMBOLS=0 \
#    -s MALLOC=emmalloc \
#    -s FORCE_FILESYSTEM=1 \

echo "Web build complete: build/index.html"

