//! Core data model for `gpen`.
//!
//! The types in this module intentionally stay close to Grease Pencil v3 concepts
//! while remaining independent from Blender headers and runtime ownership rules.

const std = @import("std");

/// Sentinel value for optional indices stored in dense arrays.
pub const invalid_index: u32 = std.math.maxInt(u32);

/// Three-dimensional vector used for transforms, bounds, and node colors.
pub const Vec3 = extern struct {
    x: f32,
    y: f32,
    z: f32,
};

/// RGBA color stored as linear floating-point channels.
pub const Color4 = extern struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
};

/// Half-open range into a dense array.
pub const IndexRange = extern struct {
    start: u32,
    len: u32,

    /// Returns the exclusive end of the range.
    pub fn end(self: IndexRange) u32 {
        return self.start + self.len;
    }
};

/// Flags attached to a point sample.
pub const PointFlags = packed struct(u16) {
    selected: bool = false,
    locked: bool = false,
    filled: bool = false,
    reserved: u13 = 0,
};

/// Per-point stroke sample with geometry, style, and input metadata.
pub const Point = extern struct {
    x: f32,
    y: f32,
    z: f32,
    radius: f32,
    opacity: f32,
    pressure: f32,
    time: f32,
    uv_rotation: f32,
    color: Color4,
    flags: u16,
    _pad0: u16,
};

/// Shape used for the ends of a stroke.
pub const StrokeCapType = enum(u8) {
    round,
    flat,
};

/// Interpolation mode for a stroke.
pub const CurveType = enum(u8) {
    catmull_rom,
    poly,
    bezier,
    nurbs,
};

/// Flags attached to a stroke.
pub const StrokeFlags = packed struct(u16) {
    cyclic: bool = false,
    selected: bool = false,
    hidden: bool = false,
    fill_visible: bool = false,
    reserved: u12 = 0,
};

/// A single stroke containing point samples and style metadata.
pub const Stroke = struct {
    points: []Point,
    curve_type: CurveType = .poly,
    material_index: u16 = 0,
    start_cap: StrokeCapType = .round,
    end_cap: StrokeCapType = .round,
    softness: f32 = 1.0,
    fill_color: Color4 = rgba(0, 0, 0, 0),
    fill_id: u32 = 0,
    flags: StrokeFlags = .{},
};

/// Dirty-state flags for drawings.
pub const DrawingFlags = packed struct(u16) {
    selected: bool = false,
    dirty_positions: bool = false,
    dirty_topology: bool = false,
    dirty_texture: bool = false,
    reserved: u12 = 0,
};

/// Owned drawing made of one or more strokes.
pub const Drawing = struct {
    strokes: []Stroke,
    name: []const u8 = "",
    bounds_min: Vec3 = vec3(0, 0, 0),
    bounds_max: Vec3 = vec3(0, 0, 0),
    flags: DrawingFlags = .{},
};

/// Reference to drawings owned by another document or asset.
pub const DrawingReference = struct {
    source_document_id: u64 = 0,
    drawing_range: IndexRange = .{ .start = 0, .len = 0 },
};

/// Tag for the drawing-slot union.
pub const DrawingSlotType = enum(u8) {
    drawing,
    reference,
};

/// Slot that stores either an owned drawing or an external reference.
pub const DrawingSlot = union(DrawingSlotType) {
    drawing: Drawing,
    reference: DrawingReference,
};

/// Flags attached to a timeline frame.
pub const FrameFlags = packed struct(u16) {
    selected: bool = false,
    implicit_hold: bool = false,
    reserved: u14 = 0,
};

/// Timeline keyframe classification.
pub const KeyframeType = enum(u8) {
    keyframe,
    extreme,
    breakdown,
    jitter,
    move_hold,
};

/// Frame mapping a timeline position to a drawing slot.
pub const Frame = struct {
    frame_number: i32,
    drawing_index: u32,
    duration: u16 = 0,
    key_type: KeyframeType = .keyframe,
    flags: FrameFlags = .{},

    /// Returns whether the frame should be held until another frame overrides it.
    pub fn isImplicitHold(self: Frame) bool {
        return self.duration == 0 or self.flags.implicit_hold;
    }
};

/// Flags attached to a layer mask.
pub const LayerMaskFlags = packed struct(u16) {
    hidden: bool = false,
    inverted: bool = false,
    reserved: u14 = 0,
};

/// Reference from one layer to another mask layer.
pub const LayerMask = struct {
    layer_index: u32,
    flags: LayerMaskFlags = .{},
};

/// Layer blending mode.
pub const LayerBlendMode = enum(u8) {
    none,
    hardlight,
    add,
    subtract,
    multiply,
    divide,
};

/// Shared node and layer flags derived from GP-style visibility and locking state.
pub const LayerFlags = packed struct(u32) {
    hidden: bool = false,
    locked: bool = false,
    selected: bool = false,
    muted: bool = false,
    use_lights: bool = false,
    hide_onion_skin: bool = false,
    expanded: bool = false,
    hide_masks: bool = false,
    disable_masks_in_viewlayer: bool = false,
    ignore_locked_materials: bool = false,
    reserved: u22 = 0,
};

/// Optional parenting information for a layer.
pub const LayerParent = struct {
    object_name: []const u8 = "",
    bone_name: []const u8 = "",
};

/// Editable transform stored on a layer.
pub const Transform = extern struct {
    translation: Vec3,
    rotation_euler: Vec3,
    scale: Vec3,
};

/// Timeline layer containing frames and layer-local settings.
pub const Layer = struct {
    name: []const u8,
    frames: []Frame,
    masks: []LayerMask = &.{},
    blend_mode: LayerBlendMode = .none,
    opacity: f32 = 1.0,
    parent: LayerParent = .{},
    transform: Transform = identityTransform(),
    parent_inverse: [4][4]f32 = identityMatrix4x4(),
    view_layer_name: []const u8 = "",
    flags: LayerFlags = .{},
};

/// UI color tag for a layer group.
pub const GroupColorTag = enum(i8) {
    none = -1,
    color_01 = 0,
    color_02 = 1,
    color_03 = 2,
    color_04 = 3,
    color_05 = 4,
    color_06 = 5,
    color_07 = 6,
    color_08 = 7,
};

/// Kind of flattened layer-tree node.
pub const LayerTreeNodeKind = enum(u8) {
    layer,
    group,
};

/// Flattened tree node that references either a layer or a layer group.
pub const LayerTreeNode = struct {
    name: []const u8,
    kind: LayerTreeNodeKind,
    item_index: u32,
    parent_index: u32 = invalid_index,
    child_range: IndexRange = .{ .start = 0, .len = 0 },
    color: Vec3 = vec3(0, 0, 0),
    color_tag: GroupColorTag = .none,
    flags: LayerFlags = .{},

    /// Returns whether the node belongs to another parent node.
    pub fn hasParent(self: LayerTreeNode) bool {
        return self.parent_index != invalid_index;
    }
};

/// Group payload referenced by layer-tree nodes of kind `group`.
pub const LayerGroup = struct {
    name: []const u8,
    color_tag: GroupColorTag = .none,
};

/// Material reference stored independently from Blender runtime pointers.
pub const MaterialSlot = struct {
    stable_id: u64 = 0,
    name: []const u8 = "",
};

/// Onion-skinning strategy.
pub const OnionSkinningMode = enum(u8) {
    absolute,
    relative,
    selected,
};

/// Flags controlling onion-skinning behavior.
pub const OnionSkinningFlags = packed struct(u8) {
    use_custom_colors: bool = true,
    use_fade: bool = true,
    show_loop: bool = false,
    reserved: u5 = 0,
};

/// Keyframe-type filter used by onion skinning.
pub const OnionSkinningFilter = packed struct(u8) {
    keyframe: bool = true,
    extreme: bool = true,
    breakdown: bool = true,
    jitter: bool = true,
    move_hold: bool = true,
    reserved: u3 = 0,
};

/// Document-level onion-skinning settings.
pub const OnionSkinningSettings = struct {
    opacity: f32 = 0.5,
    mode: OnionSkinningMode = .relative,
    flags: OnionSkinningFlags = .{},
    filter: OnionSkinningFilter = .{},
    frames_before: i16 = 1,
    frames_after: i16 = 1,
    color_before: Color4 = rgba(0.145098, 0.419608, 0.137255, 1.0),
    color_after: Color4 = rgba(0.12549, 0.082353, 0.529412, 1.0),
};

/// Document-wide flags matching high-level GP-style behavior.
pub const DocumentFlags = packed struct(u32) {
    anim_channels_expanded: bool = true,
    autolock_layers: bool = false,
    stroke_order_3d: bool = false,
    reserved: u29 = 0,
};

/// Top-level drawing document made of dense arrays and index-based links.
pub const Document = struct {
    drawings: []DrawingSlot = &.{},
    nodes: []LayerTreeNode = &.{},
    layers: []Layer = &.{},
    groups: []LayerGroup = &.{},
    materials: []MaterialSlot = &.{},
    active_node_index: u32 = invalid_index,
    onion_skinning: OnionSkinningSettings = .{},
    flags: DocumentFlags = .{},

    /// Returns whether the document currently points at an active tree node.
    pub fn hasActiveNode(self: Document) bool {
        return self.active_node_index != invalid_index;
    }
};

/// Constructs a three-dimensional vector.
pub fn vec3(x: f32, y: f32, z: f32) Vec3 {
    return .{ .x = x, .y = y, .z = z };
}

/// Constructs an RGBA color.
pub fn rgba(r: f32, g: f32, b: f32, a: f32) Color4 {
    return .{ .r = r, .g = g, .b = b, .a = a };
}

/// Returns the default identity transform.
pub fn identityTransform() Transform {
    return .{
        .translation = vec3(0, 0, 0),
        .rotation_euler = vec3(0, 0, 0),
        .scale = vec3(1, 1, 1),
    };
}

/// Returns a 4x4 identity matrix.
pub fn identityMatrix4x4() [4][4]f32 {
    return .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    };
}

/// Constructs a convenient 2D point sample for tests and simple callers.
pub fn point2(x: f32, y: f32, pressure: f32, time: f32) Point {
    return .{
        .x = x,
        .y = y,
        .z = 0,
        .radius = pressure,
        .opacity = 1.0,
        .pressure = pressure,
        .time = time,
        .uv_rotation = 0,
        .color = rgba(0, 0, 0, 1),
        .flags = @bitCast(PointFlags{}),
        ._pad0 = 0,
    };
}

/// Duplicates a point slice into caller-owned memory.
pub fn clonePoints(allocator: std.mem.Allocator, points: []const Point) ![]Point {
    const dup = try allocator.alloc(Point, points.len);
    @memcpy(dup, points);
    return dup;
}

test "frame defaults to implicit hold when duration is zero" {
    const frame = Frame{
        .frame_number = 12,
        .drawing_index = 3,
    };
    try std.testing.expect(frame.isImplicitHold());
}

test "document stores tree links with dense indices" {
    const node = LayerTreeNode{
        .name = "Ink",
        .kind = .layer,
        .item_index = 0,
    };
    try std.testing.expect(!node.hasParent());
    try std.testing.expectEqual(invalid_index, node.parent_index);
}
