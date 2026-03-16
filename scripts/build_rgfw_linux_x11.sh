#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJ_ROOT="$DIR/.."
DEPS_DIR="$PROJ_ROOT/deps/RGFW_linux_amd64"
RGFW_DIR="$DIR/RGFW"

if [ ! -d "$RGFW_DIR" ]; then
    echo "Cloning RGFW..."
    git clone --depth 1 https://github.com/ColleagueRiley/RGFW.git "$RGFW_DIR"
fi

cd "$RGFW_DIR"
cp RGFW.h RGFW.c
cc -O3 -D RGFW_UNIX -D RGFW_X11 -fPIC -c RGFW.c -D RGFW_IMPLEMENTATION -D RGFW_EXPORT -o RGFW.o
rm RGFW.c

ar rcs libRGFW_x11.a RGFW.o
mkdir -p "$DEPS_DIR/lib"
mkdir -p "$DEPS_DIR/include"
cp libRGFW_x11.a "$DEPS_DIR/lib/"
cp RGFW.h "$DEPS_DIR/include/"

echo "Successfully built libRGFW_x11.a with X11 support!"
