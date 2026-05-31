# Proto Boundary

`gpen` uses protobuf as the canonical format for:

- file storage
- cross-runtime transport
- sync/import/export payloads

It does **not** use protobuf as a byte-for-byte mirror of Zig structs or Blender DNA.

## Proto Side

The canonical schema lives in [protocol/gpen/v1/model.proto](/home/n/document/code/gpen/protocol/gpen/v1/model.proto:1).

These parts belong in proto because they define the durable document state:

- document graph: `Document`, `DrawingSlot`, `LayerTreeNode`, `Layer`, `LayerGroup`
- timeline mapping: `Frame`, `KeyframeType`
- material references: `MaterialSlot`
- onion-skinning settings
- stroke and point content:
  - point position, radius, opacity, pressure, time, UV rotation, point flags
  - stroke curve type, caps, softness, fill color, fill id, material index
- stable references represented as ids, names, ranges, or indices

These fields are appropriate for both storage and transport because another runtime can reconstruct
the same editable document from them without depending on allocator layout, host pointers, or
Blender internals.

## Non-Proto Side

The following parts stay outside protobuf and should remain runtime-only or ABI-only:

- C ABI wrappers in [src/abi/c_api.zig](/home/n/document/code/gpen/src/abi/c_api.zig:1)
- WASM ABI wrappers in [src/abi/wasm.zig](/home/n/document/code/gpen/src/abi/wasm.zig:1)
- pointer/length headers, allocators, arena lifetime, `gp_*` exported functions
- intrusive pointers and linked-list layout from Blender DNA
- Blender runtime pointers like `Object *`, `Material *`, `runtime *`
- generic attribute storage implementation details
- caches and derived data:
  - bounds
  - triangulation / fills cache
  - texture matrices cache
  - user counts
  - dirty flags used only for recomputation

Those values are process-local implementation details. They can always be rebuilt from the proto
document plus host context.

## Translation Rule

Use this rule when deciding whether a field belongs in proto:

- Put it in proto when another process or another saved file needs it to reconstruct the same
  document semantics.
- Keep it out of proto when it only exists to speed up computation, manage ownership, or satisfy a
  specific ABI.

## Current Mapping Notes

- Blender `GreasePencilDrawing.geometry` is represented in `gpen` proto as explicit `Stroke` and
  `Point` messages, rather than as `CurvesGeometry + custom attributes`.
- Blender intrusive tree/list ownership becomes dense arrays plus indices and `IndexRange`.
- Runtime-only drawing bounds and dirty flags are intentionally excluded from proto even if the Zig
  in-memory model keeps equivalent concepts for processing convenience.
- A few editor-visible flags still remain in proto today because they affect user-facing document
  state; if needed later, they can be split into a separate session-state schema.
