//! WebAssembly ABI for `gpen`.
//!
//! This module exposes a compact result header and an arena-backed allocation
//! strategy suitable for browser and webview hosts.

const std = @import("std");
const gpen = @import("gpen");

pub const GpenWasmStatus = enum(u32) {
    ok = 0,
    null_pointer = 1,
    alloc_failed = 2,
};

/// Compact input point used by the browser demo.
pub const WasmInputPoint = extern struct {
    x: f32,
    y: f32,
    pressure: f32,
    time: f32,
};

/// Compact output point returned to the browser demo.
pub const WasmOutputPoint = extern struct {
    x: f32,
    y: f32,
    pressure: f32,
};

/// Pointer-length header returned by the WASM ABI.
pub const WasmResultHeader = extern struct {
    ptr: u32,
    len: u32,
};

var arena = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);

/// Resets temporary arena allocations performed by the WASM ABI.
pub export fn gp_reset_arena() void {
    _ = arena.reset(.retain_capacity);
}

/// Returns the byte size of a single demo input point.
pub export fn gp_input_point_size_wasm() u32 {
    return @sizeOf(WasmInputPoint);
}

/// Returns the byte size of a single demo output point.
pub export fn gp_output_point_size_wasm() u32 {
    return @sizeOf(WasmOutputPoint);
}

/// Allocates input-point storage in linear memory for browser hosts.
pub export fn gp_alloc_input_points_wasm(point_count: u32) u32 {
    if (point_count == 0) return 0;
    const points = arena.allocator().alloc(WasmInputPoint, point_count) catch return 0;
    return @intCast(@intFromPtr(points.ptr));
}

/// Allocates a result header in linear memory for browser hosts.
pub export fn gp_alloc_result_header_wasm() u32 {
    const header = arena.allocator().create(WasmResultHeader) catch return 0;
    return @intCast(@intFromPtr(header));
}

/// Processes a point slice and returns the output slice location in linear memory.
pub export fn gp_process_stroke_wasm(
    input_ptr: [*]const gpen.Point,
    input_len: usize,
    options: gpen.ProcessOptions,
) WasmResultHeader {
    const allocator = arena.allocator();
    const input = input_ptr[0..input_len];
    const result = gpen.stroke.processStroke(allocator, input, options) catch {
        return .{ .ptr = 0, .len = 0 };
    };
    return .{
        .ptr = @intCast(@intFromPtr(result.points.ptr)),
        .len = @intCast(result.points.len),
    };
}

/// Processes browser demo samples into a compact output-point buffer.
pub export fn gp_process_stroke_web_wasm(
    input_ptr: u32,
    input_len: u32,
    smooth_passes: u32,
    simplify_epsilon: f32,
    width_gain: f32,
    out_header_ptr: u32,
) GpenWasmStatus {
    if (input_len > 0 and input_ptr == 0) return .null_pointer;
    if (out_header_ptr == 0) return .null_pointer;

    const allocator = arena.allocator();
    const input_samples = @as([*]const WasmInputPoint, @ptrFromInt(input_ptr))[0..input_len];
    const input_points = allocator.alloc(gpen.Point, input_len) catch return .alloc_failed;

    for (input_samples, input_points) |sample, *point| {
        point.* = gpen.model.point2(sample.x, sample.y, sample.pressure, sample.time);
        point.radius = @max(sample.pressure, 0.1);
    }

    const result = gpen.stroke.processStroke(allocator, input_points, .{
        .smooth_passes = smooth_passes,
        .simplify_epsilon = simplify_epsilon,
        .width_gain = width_gain,
    }) catch return .alloc_failed;

    const output_points = allocator.alloc(WasmOutputPoint, result.points.len) catch return .alloc_failed;
    for (result.points, output_points) |point, *output| {
        output.* = .{
            .x = point.x,
            .y = point.y,
            .pressure = point.pressure,
        };
    }

    const header = @as(*WasmResultHeader, @ptrFromInt(out_header_ptr));
    header.* = .{
        .ptr = @intCast(@intFromPtr(output_points.ptr)),
        .len = @intCast(output_points.len),
    };
    return .ok;
}
