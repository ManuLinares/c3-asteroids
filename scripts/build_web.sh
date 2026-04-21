#!/bin/bash
set -e
emcc build/obj/wasm32/*.wasm \
    deps/RGFW_wasm/lib/libRGFW_wasm.a \
    deps/miniaudio_wasm/lib/libminiaudio.a \
    -o build/index.html \
    --shell-file lib/shell.html \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s "EXPORTED_RUNTIME_METHODS=['requestFullscreen','HEAPU8']" \
    -s "EXPORTED_FUNCTIONS=['_main','_start_web_game','_malloc','_free']" \
    -s "DEFAULT_LIBRARY_FUNCS_TO_INCLUDE=['\$stringToNewUTF8']" \
    -O2
