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
WAYLAND_OBJS=""
make -f wayland.mk

for csrc in xdg-shell.c xdg-toplevel-icon-v1.c xdg-decoration-unstable-v1.c \
    relative-pointer-unstable-v1.c pointer-constraints-unstable-v1.c \
    xdg-output-unstable-v1.c pointer-warp-v1.c; do
    if [ -f "$csrc" ]; then
        obj="${csrc%.c}.o"
        cc -O3 -fPIC -c "$csrc" -o "$obj"
        WAYLAND_OBJS="$WAYLAND_OBJS $obj"
    fi
done

cp RGFW.h RGFW.c
sed -i 's/#define RGFW_DEBUG/\/\/#define RGFW_DEBUG/g' RGFW.c
cc -O3 -D RGFW_UNIX -D RGFW_WAYLAND -fPIC -c RGFW.c -D RGFW_IMPLEMENTATION -D RGFW_EXPORT -o RGFW.o
rm RGFW.c

# Bundle everything into libRGFW_wayland.a
ar rcs libRGFW_wayland.a RGFW.o $WAYLAND_OBJS

mkdir -p "$DEPS_DIR/lib"
mkdir -p "$DEPS_DIR/include"
cp libRGFW_wayland.a "$DEPS_DIR/lib/"
cp RGFW.h "$DEPS_DIR/include/"

echo "Successfully built libRGFW_wayland.a with native Wayland support!"
