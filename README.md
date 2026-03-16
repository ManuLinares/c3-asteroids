# Asteroids

Asteroids clone written in C3. Software-rendered. Window and input via [RGFW](https://github.com/ColleagueRiley/RGFW). Audio via [miniaudio](https://miniaud.io).

You can play it in the browser: https://manulinares.github.io/c3-asteroids/

## Demo

[![Asteroids gameplay](https://img.youtube.com/vi/hHuq6c-NRUs/maxresdefault.jpg)](https://www.youtube.com/watch?v=hHuq6c-NRUs)

## Dependencies

- [C3 compiler](https://c3-lang.org) (`c3c` in PATH)
- On Linux: `gcc`, `clang`, `wayland-scanner`, `git`, and dev libraries for X11/Wayland.
- For Windows cross-compilation: `mingw-w64`.
- For Web: [Emscripten](https://emscripten.org/).

## Build and Run

The build system automatically compiles necessary C dependencies on the first run.

### Linux (X11/Wayland)

```sh
c3c run linux --trust=full
```

### Web (WASM)

```sh
c3c build web --trust=full
# Serve the build/ directory using any local web server
```

### Windows (Cross-compilation from Linux)

```sh
c3c build windows --trust=full
# Run the resulting asteroids.exe
```

## Controls

| Key | Action |
|-----|--------|
| WASD/Arrow Keys | Thrust, Rotate, Brake |
| Space | Fire |
| E | Hyperspace |
| Escape | Quit |
| P | Pause |
| C | Cheat mode |

---
> [!TIP]
> Use `--trust=full` when running/building to allow the `project.json` to execute the dependency build scripts.
