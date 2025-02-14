const std = @import("std");

pub const Value = union(enum) {
    Integer: i64,
    FloatingPoint: f64,

    pub fn negate(self: Value) Value {
        const self_tag: std.meta.Tag(Value) = @enumFromInt(@intFromEnum(self));
        switch (self_tag) {
            inline else => |tag| {
                const value = @field(self, @tagName(tag));
                return @unionInit(Value, @tagName(tag), -value);
            },
        }
    }

    pub fn add(left: Value, right: Value) !Value {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(Value) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                return @unionInit(Value, @tagName(tag), lvalue + rvalue);
            },
        }
    }

    pub fn subtract(left: Value, right: Value) !Value {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(Value) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                return @unionInit(Value, @tagName(tag), lvalue - rvalue);
            },
        }
    }

    pub fn multiply(left: Value, right: Value) !Value {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(Value) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                return @unionInit(Value, @tagName(tag), lvalue * rvalue);
            },
        }
    }

    pub fn divide(left: Value, right: Value) !Value {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(Value) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                if (rvalue == 0)
                    return error.ZeroDivision;

                return @unionInit(Value, @tagName(tag), @divTrunc(lvalue, rvalue));
            },
        }
    }

    pub fn format(self: Value, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            inline else => |value| try std.fmt.format(writer, "{any}", .{value}),
        }
    }
};
