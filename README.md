# gpen

Shared Zig core for a Grease Pencil-style stroke engine, with host scaffolds for:

- browser extensions on Chrome and Firefox
- VS Code extension packaging
- Blender Python add-on calling a native shared library

## Layout

- `src/core`: host-agnostic stroke model and algorithms
- `src/abi`: WASM and C ABI entrypoints
- `protocol`: versioned protobuf schemas for storage and cross-runtime transport
- `hosts/browser-ext`: WebExtensions scaffold
- `hosts/vscode-ext`: VS Code host scaffold
- `hosts/blender-addon`: Blender add-on scaffold

## Protobuf Schema

The canonical serialized document schema lives under `protocol/gpen/v1`.
It is intended for persistence and cross-runtime transport rather than
byte-for-byte mirroring the Zig in-memory ABI.

## Build

```sh
zig build test --global-cache-dir ./.zig-global-cache --cache-dir ./.zig-cache
zig build --global-cache-dir ./.zig-global-cache --cache-dir ./.zig-cache
/home/n/.pixi/bin/zig build demo --global-cache-dir ./.zig-global-cache --cache-dir ./.zig-cache
```
