#!/bin/bash
set -e

TARGET=$1
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJ_ROOT="$DIR/.."
MA_HEADER="$PROJ_ROOT/deps/miniaudio/miniaudio.h"

# Common defines for all platforms
MA_DEFS="-DMINIAUDIO_IMPLEMENTATION -DMA_NO_DECODING -DMA_NO_ENCODING -DMA_NO_GENERATION -DMA_NO_NODE_GRAPH -DMA_NO_RESOURCE_MANAGER -DMA_NO_ENGINE -DMA_NO_JACK -DMA_NO_OSS -DMA_NO_SNDIO -DMA_NO_DSOUND -DMA_NO_WINMM -DMA_NO_WAV -DMA_NO_MP3 -DMA_NO_FLAC -DMA_NO_STDIO -DMA_NO_AAUDIO -DMA_NO_OPENSL -DMA_NO_COREAUDIO -DMA_NO_AUDIO4 -DMA_NO_CUSTOM"

case $TARGET in
    linux)
        echo "Building miniaudio for Linux..."
        OUT_DIR="$PROJ_ROOT/deps/miniaudio_linux_amd64/lib"
        mkdir -p "$OUT_DIR"
        cc -O3 -fPIC -x c -c "$MA_HEADER" -o miniaudio.o $MA_DEFS -DMA_NO_WEBAUDIO
        ar rcs "$OUT_DIR/libminiaudio.a" miniaudio.o
        rm miniaudio.o
        ;;
    wasm)
        echo "Building miniaudio for WASM..."
        OUT_DIR="$PROJ_ROOT/deps/miniaudio_wasm/lib"
        mkdir -p "$OUT_DIR"
        emcc -O3 -x c -c "$MA_HEADER" -o miniaudio.o $MA_DEFS
        emar rcs "$OUT_DIR/libminiaudio.a" miniaudio.o
        rm miniaudio.o
        ;;
    windows)
        echo "Building miniaudio for Windows (Cross-compile)..."
        OUT_DIR="$PROJ_ROOT/deps/miniaudio_windows_amd64/lib"
        mkdir -p "$OUT_DIR"
        # Use gnu target to find headers on Linux, but disable MinGW's custom stdio to match MSVC/UCRT symbols
        clang -O3 -target x86_64-pc-windows-gnu -mno-stack-arg-probe \
              -D__USE_MINGW_ANSI_STDIO=0 -Dvsnprintf=_vsnprintf -Dsnprintf=_snprintf \
              -x c -c "$MA_HEADER" -o "$OUT_DIR/miniaudio.obj" $MA_DEFS -DMA_NO_WEBAUDIO
        ;;
    *)
        echo "Usage: $0 {linux|wasm|windows}"
        exit 1
        ;;
esac

echo "Done!"
