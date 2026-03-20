#!/bin/bash
set -e

TARGET=$1
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RGFW_DIR="$DIR/RGFW"
RGFW_TAG="1.8.1"

[ -d "$RGFW_DIR" ] || git clone --depth 1 --branch "$RGFW_TAG" https://github.com/ColleagueRiley/RGFW.git "$RGFW_DIR"
cd "$RGFW_DIR"

case $TARGET in
	linux)
		echo "Building RGFW for Linux (X11 + Wayland)..."
		DEPS_DIR="../../deps/RGFW_linux_amd64"
		LIB_NAME="libRGFW.a"

		make -f wayland.mk protocols 2>/dev/null || make -f wayland.mk
		WAYLAND_OBJS=""
		for csrc in xdg-shell.c xdg-toplevel-icon-v1.c xdg-decoration-unstable-v1.c relative-pointer-unstable-v1.c pointer-constraints-unstable-v1.c xdg-output-unstable-v1.c pointer-warp-v1.c; do
			[ -f "$csrc" ] && cc -O3 -fPIC -c "$csrc" -o "${csrc%.c}.o" && WAYLAND_OBJS="$WAYLAND_OBJS ${csrc%.c}.o"
		done
		cc -O3 -fPIC -D RGFW_X11 -D RGFW_WAYLAND -D RGFW_IMPLEMENTATION -x c -c RGFW.h -o RGFW.o
		ar rcs "$LIB_NAME" RGFW.o $WAYLAND_OBJS
		;;
	wasm)
		echo "Building RGFW for WASM..."
		DEPS_DIR="../../deps/RGFW_wasm"
		LIB_NAME="libRGFW_wasm.a"

		sed 's/emscripten_sleep(0);//g' RGFW.h > RGFW_temp.c
		emcc -O3 -c RGFW_temp.c -D RGFW_IMPLEMENTATION -D RGFW_EXPORT -o RGFW_wasm.o
		emar rcs "$LIB_NAME" RGFW_wasm.o
		rm RGFW_temp.c
		;;
	*) echo "Usage: $0 {linux|wasm}"; exit 1 ;;
esac

mkdir -p "$DEPS_DIR/lib" "$DEPS_DIR/include"
cp "$LIB_NAME" "$DEPS_DIR/lib/"
cp RGFW.h "$DEPS_DIR/include/"
echo "Done!"
