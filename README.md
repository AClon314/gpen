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

## Licensing

This repository uses a dual-license model.

- Community use defaults to `AGPL-3.0-or-later`.
- Closed-source distribution, proprietary embedding, or other use outside the
  AGPL is available only after purchasing a separate written commercial license
  from the copyright holder.
- The commercial option described in `LICENSE-Commercial.md` is part of that
  licensing path only. It does not apply automatically to public users of this
  repository.
- `gpen-protocol` and `gpen-ui-js` are exceptions: they are publicly available
  under Apache License 2.0 so the protocol can be reused as an open standard
  and the UI components can be reused by other frontend projects.

All contributors must sign a `CLA` before a contribution can be accepted. By
signing that `CLA`, contributors agree that their contributions may be
distributed under both `AGPL-3.0-or-later` and separate commercial licenses.

The `gpen` name, logos, icons, and other brand assets are not automatically
licensed with the source code. See [LICENSE-AGPLv3.md](LICENSE-AGPLv3.md),
[LICENSE-Commercial.md](LICENSE-Commercial.md), [TRADEMARKS.md](TRADEMARKS.md), and
[CONTRIBUTE.md](CONTRIBUTE.md).
