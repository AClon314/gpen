//! Public package surface for `gpen`.
//!
//! This module re-exports the core data model and the first stroke-processing API
//! so downstream users can import a single package entrypoint.

/// Core data-model types and helpers.
pub const model = @import("core/model.zig");
/// Stroke-processing algorithms.
pub const stroke = @import("core/stroke.zig");

/// Three-dimensional vector used by transforms, bounds, and node colors.
pub const Vec3 = model.Vec3;
/// RGBA color value used for stroke and fill colors.
pub const Color4 = model.Color4;
/// Per-point stroke sample compatible with the `gpen` drawing model.
pub const Point = model.Point;
/// A single stroke made of a contiguous point slice plus style metadata.
pub const Stroke = model.Stroke;
/// A drawing containing one or more strokes.
pub const Drawing = model.Drawing;
/// Tagged slot that stores either an owned drawing or a drawing reference.
pub const DrawingSlot = model.DrawingSlot;
/// Timeline frame pointing at a drawing slot.
pub const Frame = model.Frame;
/// Layer containing frame mappings and layer-specific settings.
pub const Layer = model.Layer;
/// Layer-group payload referenced by the flattened tree.
pub const LayerGroup = model.LayerGroup;
/// Flattened layer-tree node used by the document structure.
pub const LayerTreeNode = model.LayerTreeNode;
/// Top-level document made of drawings, layers, groups, and materials.
pub const Document = model.Document;
/// Options controlling the minimal stroke processing pipeline.
pub const ProcessOptions = stroke.ProcessOptions;
/// Result returned by the minimal stroke processing pipeline.
pub const ProcessResult = stroke.ProcessResult;

test {
    _ = @import("core/model.zig");
    _ = @import("core/stroke.zig");
}
