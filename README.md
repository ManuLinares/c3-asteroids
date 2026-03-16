# Asteroids

Asteroids clone written in C3. Software-rendered. Window and input via [RGFW](https://github.com/ColleagueRiley/RGFW).

You can play it in the browser: https://manulinares.github.io/c3-asteroids/

## Demo

[![Asteroids gameplay](https://img.youtube.com/vi/hHuq6c-NRUs/maxresdefault.jpg)](https://www.youtube.com/watch?v=hHuq6c-NRUs)

## Dependencies

- [C3 compiler](https://c3-lang.org) (`c3c` in PATH)
- On Linux: `gcc`, `clang` + `mingw-w64` (for Windows cross-compilation), `wayland-scanner`, `git`, and the usual Wayland/X11 dev libraries depending on the target
- For Web: [Emscripten](https://emscripten.org/)

## Build

### Linux

Build the RGFW library:

```sh
c3c build deps-wayland --trust=full #or `c3c build deps-x11 --trust=full` for X11
c3c build asteroids_linux_wayland
```
<small>run `./build/asteroids_linux_wayland`</small>

### Web (WASM)

```sh
c3c build deps-web --trust=full
c3c build asteroids_web --trust=full
```
<small>open `build/asteroids.html` in a browser</small>

### Windows (Cross-compilation from Linux)

```sh
c3c build deps-windows --trust=full
c3c build asteroids_windows
```
<small>run `build/asteroids_windows.exe`</small>

> [!NOTE]
> Windows cross-compilation requires `clang` to build the miniaudio dependency.

## Controls

| Key | Action |
|-----|--------|
| W / Up | Thrust |
| A / Left | Rotate left |
| S / Down | Brake |
| D / Right | Rotate right |
| Space | Fire |
| E | Hyperspace |
| Escape | Quit |
| P | Pause |
| C | Cheat mode |
