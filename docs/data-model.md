# GPen Data Model

`gpen` tracks the Grease Pencil v3 object model closely enough to stay compatible in shape, but it
does not mirror Blender's storage verbatim.

## Kept close to GP v3

- document -> drawings + layers + layer groups + node tree
- frame -> drawing index + keyframe metadata
- layer -> masks + parent link + transform + view-layer routing
- drawing -> strokes and point-domain attributes
- stroke/point attributes -> radius, opacity, pressure, time, UV rotation, vertex/fill color

## Intentional divergences

- `ListBaseT` linked lists become dense arrays plus `IndexRange`.
- Blender runtime pointers and caches are removed from the persistent model.
- tree ownership uses stable indices instead of intrusive next/prev pointers.
- material references are stored as stable ids plus names, not Blender `Material *`.
- drawing references stay explicit, but reference external document ids instead of `ID *`.

## Why this is better for `gpen`

- easier WASM/native serialization
- simpler undo snapshots and diffing
- cache-friendly traversal for stroke processing
- no dependence on Blender C++ headers or allocator model

See [proto-boundary.md](/home/n/document/code/gpen/docs/proto-boundary.md:1) for the split between
canonical protobuf document state and runtime-only implementation state.

## Fields worth optimizing beyond GP v3

- point positions stay AoS for now, but hot render/edit paths may want SoA packing later
- frame storage should move to sorted arrays with binary search, not map-like storage structs
- layer tree can be flattened once and traversed by ranges instead of pointer chasing
- transient caches like bounds, triangulation, texture matrices should live in runtime sidecars
- string-heavy references like parent object/bone names should eventually intern to ids
