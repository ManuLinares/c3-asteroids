#!/bin/bash
set -e

echo "Building Asteroids for Web..."

echo "Compiling object files..."
OBJ_DIR="build/obj/wasm32"
rm -rf "$OBJ_DIR"
c3c build web_objs -O0 --safe=no --link-libc=yes

echo "Linking..."
DEPS_DIR="deps"
OUTPUT_DIR="build"
OBJS=$(find "$OBJ_DIR" -name "*.wasm")

emcc $OBJS \
    "$DEPS_DIR/RGFW_wasm/lib/libRGFW_wasm.a" \
    -o "$OUTPUT_DIR/asteroids.html" \
    --shell-file lib/shell.html \
    -s FORCE_FILESYSTEM=1 \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s STACK_SIZE=4194304 \
    -s MALLOC=emmalloc \
    -s ASYNCIFY=1 \
    -s "EXPORTED_RUNTIME_METHODS=['requestFullscreen', 'HEAPU8']" \
    -s "DEFAULT_LIBRARY_FUNCS_TO_INCLUDE=['\$stringToNewUTF8']" \
    -O0

echo "Web build complete: build/asteroids.html"

# Copy to web/ folder for pre-built deployment, remove this when c3c adds libc to thread_none NOTE: TODO: control+f : Manu
WEB_DIR="web"
mkdir -p "$WEB_DIR"
cp "$OUTPUT_DIR/asteroids.html" "$WEB_DIR/index.html"
cp "$OUTPUT_DIR/asteroids.html" "$WEB_DIR/asteroids.html"
cp "$OUTPUT_DIR/asteroids.js" "$WEB_DIR/"
cp "$OUTPUT_DIR/asteroids.wasm" "$WEB_DIR/"

echo "Assets copied to $WEB_DIR/ for deployment."
