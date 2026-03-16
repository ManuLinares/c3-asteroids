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

echo "Building Unified RGFW (X11 + Wayland)..."

# 1. Generate Wayland protocols
make -f wayland.mk protocols 2>/dev/null || make -f wayland.mk

# 2. Compile Wayland protocol objects
WAYLAND_OBJS=""
for csrc in xdg-shell.c xdg-toplevel-icon-v1.c xdg-decoration-unstable-v1.c \
    relative-pointer-unstable-v1.c pointer-constraints-unstable-v1.c \
    xdg-output-unstable-v1.c pointer-warp-v1.c; do
    if [ -f "$csrc" ]; then
        obj="${csrc%.c}.o"
        cc -O3 -fPIC -c "$csrc" -o "$obj"
        WAYLAND_OBJS="$WAYLAND_OBJS $obj"
    fi
done

# 3. Compile RGFW with BOTH backends enabled
# Note: RGFW_X11 and RGFW_WAYLAND together enables the dynamic backend. Test this now: TODO
cc -O3 -D RGFW_X11 -D RGFW_WAYLAND -D RGFW_IMPLEMENTATION -x c -c RGFW.h -o RGFW.o

# 4. Bundle everything into a single libRGFW.a
ar rcs libRGFW.a RGFW.o $WAYLAND_OBJS

# 5. Setup dependencies directory
mkdir -p "$DEPS_DIR/lib"
mkdir -p "$DEPS_DIR/include"
cp libRGFW.a "$DEPS_DIR/lib/"
cp RGFW.h "$DEPS_DIR/include/"

echo "------------------------------------------------"
echo "Successfully built unified libRGFW.a! (X11 and Wayland)"
echo "Location: $DEPS_DIR/lib/libRGFW.a"
