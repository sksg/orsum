const std = @import("std");

pub const Value = union(enum) {
    Integer: i64,
    FloatingPoint: f64,
    Boolean: bool,
    String: []const u8,

    pub fn not(self: Value) !Value {
        switch (self) {
            inline .Boolean => |value, tag| return @unionInit(Value, @tagName(tag), !value),
            else => return error.WrongType,
        }
    }

    pub fn negate(self: Value) !Value {
        const self_tag: std.meta.Tag(Value) = @enumFromInt(@intFromEnum(self));
        switch (self_tag) {
            .Boolean, .String => return error.WrongType,
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
            .Boolean, .String => return error.WrongType,
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
            .Boolean, .String => return error.WrongType,
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
            .Boolean, .String => return error.WrongType,
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
            .Boolean, .String => return error.WrongType,
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                if (rvalue == 0)
                    return error.ZeroDivision;

                return @unionInit(Value, @tagName(tag), @divTrunc(lvalue, rvalue));
            },
        }
    }

    pub fn equal(left: Value, right: Value) !Value {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(Value) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            .String => return error.WrongType,
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                return .{ .Boolean = lvalue == rvalue };
            },
        }
    }

    pub fn not_equal(left: Value, right: Value) !Value {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(Value) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            .String => return error.WrongType,
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                return .{ .Boolean = lvalue != rvalue };
            },
        }
    }

    pub fn greater_than(left: Value, right: Value) !Value {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(Value) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            .Boolean, .String => return error.WrongType,
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                return .{ .Boolean = lvalue > rvalue };
            },
        }
    }

    pub fn less_than(left: Value, right: Value) !Value {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(Value) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            .Boolean, .String => return error.WrongType,
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                return .{ .Boolean = lvalue < rvalue };
            },
        }
    }

    pub fn greater_than_or_equal(left: Value, right: Value) !Value {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(Value) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            .Boolean, .String => return error.WrongType,
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                return .{ .Boolean = lvalue >= rvalue };
            },
        }
    }

    pub fn less_than_or_equal(left: Value, right: Value) !Value {
        if (@intFromEnum(left) != @intFromEnum(right))
            return error.DifferentTypes;

        const left_tag: std.meta.Tag(Value) = @enumFromInt(@intFromEnum(left));
        switch (left_tag) {
            .Boolean, .String => return error.WrongType,
            inline else => |tag| {
                const lvalue = @field(left, @tagName(tag));
                const rvalue = @field(right, @tagName(tag));
                return .{ .Boolean = lvalue <= rvalue };
            },
        }
    }

    pub fn format(self: Value, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        switch (self) {
            inline .String => |value| try std.fmt.format(writer, "{s}", .{value}),
            inline else => |value| try std.fmt.format(writer, "{any}", .{value}),
        }
    }
};
