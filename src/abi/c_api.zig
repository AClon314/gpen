//! Native C ABI for `gpen`.
//!
//! This layer exposes the minimal stroke-processing pipeline to hosts that load
//! a shared library, such as Blender-side integration code.

const std = @import("std");
const gpen = @import("gpen");

/// Status code returned by exported C ABI calls.
pub const GpenStatus = enum(c_int) {
    ok = 0,
    null_pointer = 1,
    alloc_failed = 2,
};

/// Heap-allocated point slice returned through the C ABI.
pub const GpenSlice = extern struct {
    ptr: [*]gpen.Point,
    len: usize,
};

/// Processes a point slice and returns an owned output slice through `out_slice`.
pub export fn gp_process_stroke_c(
    input_ptr: ?[*]const gpen.Point,
    input_len: usize,
    options: gpen.ProcessOptions,
    out_slice: ?*GpenSlice,
) GpenStatus {
    if (input_len > 0 and input_ptr == null) {
        return .null_pointer;
    }
    if (out_slice == null) {
        return .null_pointer;
    }

    const allocator = std.heap.c_allocator;
    const input = input_ptr.?[0..input_len];
    const result = gpen.stroke.processStroke(allocator, input, options) catch {
        return .alloc_failed;
    };

    out_slice.?.* = .{
        .ptr = result.points.ptr,
        .len = result.points.len,
    };
    return .ok;
}

/// Frees a point slice previously allocated by `gp_process_stroke_c`.
pub export fn gp_free_points_c(ptr: ?[*]gpen.Point, len: usize) void {
    if (ptr == null or len == 0) return;
    const allocator = std.heap.c_allocator;
    allocator.free(ptr.?[0..len]);
}
