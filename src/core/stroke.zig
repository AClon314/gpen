//! Minimal stroke-processing algorithms.
//!
//! The first implementation intentionally stays small: clone the point buffer,
//! scale width-related values, and apply a basic smoothing pass.

const std = @import("std");
const model = @import("model.zig");

/// Options for the minimal stroke-processing pipeline.
pub const ProcessOptions = extern struct {
    smooth_passes: u32 = 1,
    simplify_epsilon: f32 = 0.0,
    width_gain: f32 = 1.0,
};

/// Output of the minimal stroke-processing pipeline.
pub const ProcessResult = struct {
    points: []model.Point,
};

/// Processes a single stroke worth of points into a newly allocated output slice.
pub fn processStroke(
    allocator: std.mem.Allocator,
    input: []const model.Point,
    options: ProcessOptions,
) !ProcessResult {
    const output = try model.clonePoints(allocator, input);
    applyWidthGain(output, options.width_gain);
    smoothInPlace(output, options.smooth_passes);
    _ = options.simplify_epsilon;
    return .{ .points = output };
}

fn applyWidthGain(points: []model.Point, width_gain: f32) void {
    for (points) |*point| {
        point.pressure *= width_gain;
    }
}

fn smoothInPlace(points: []model.Point, passes: u32) void {
    if (points.len < 3) return;

    var pass: u32 = 0;
    while (pass < passes) : (pass += 1) {
        var prev = points[0];
        var i: usize = 1;
        while (i + 1 < points.len) : (i += 1) {
            const current = points[i];
            const next = points[i + 1];
            points[i].x = (prev.x + current.x * 2.0 + next.x) * 0.25;
            points[i].y = (prev.y + current.y * 2.0 + next.y) * 0.25;
            prev = current;
        }
    }
}

test "process stroke preserves point count and scales pressure" {
    const allocator = std.testing.allocator;
    const input = [_]model.Point{
        model.point2(0, 0, 1, 0),
        model.point2(1, 1, 0.5, 0.1),
        model.point2(2, 0, 0.25, 0.2),
    };

    const result = try processStroke(allocator, &input, .{
        .smooth_passes = 1,
        .width_gain = 2.0,
    });
    defer allocator.free(result.points);

    try std.testing.expectEqual(@as(usize, input.len), result.points.len);
    try std.testing.expectApproxEqAbs(@as(f32, 2.0), result.points[0].pressure, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), result.points[1].pressure, 0.0001);
}
