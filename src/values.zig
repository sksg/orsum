const std = @import("std");

pub const ValueType = union(enum) {
    Integer: i64,
    FloatingPoint: f64,

    pub fn negate(self: ValueType) ValueType {
        const self_tag: std.meta.Tag(ValueType) = @enumFromInt(@intFromEnum(self));
        switch (self_tag) {
            inline else => |tag| {
                const value = @field(self, @tagName(tag));
                return @unionInit(ValueType, @tagName(tag), -value);
            },
        }
    }

    pub fn add(left: ValueType, right: ValueType) !ValueType {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(ValueType) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                return @unionInit(ValueType, @tagName(tag), lvalue + rvalue);
            },
        }
    }

    pub fn subtract(left: ValueType, right: ValueType) !ValueType {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(ValueType) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                return @unionInit(ValueType, @tagName(tag), lvalue - rvalue);
            },
        }
    }

    pub fn multiply(left: ValueType, right: ValueType) !ValueType {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(ValueType) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                return @unionInit(ValueType, @tagName(tag), lvalue * rvalue);
            },
        }
    }

    pub fn divide(left: ValueType, right: ValueType) !ValueType {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(ValueType) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                if (rvalue == 0)
                    return error.ZeroDivision;

                return @unionInit(ValueType, @tagName(tag), @divTrunc(lvalue, rvalue));
            },
        }
    }

    pub fn format(self: ValueType, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            inline else => |value| try std.fmt.format(writer, "{any}", .{value}),
        }
    }
};
