const std = @import("std");

pub const Value = @import("values.zig").Value;
pub const Address = @import("tokens.zig").Token.Address;
pub const Chunk = @import("chunks.zig").Chunk(@This());

fn Register(comptime backing_type: type) type {
    return struct { index: backing_type };
}

fn Constant(comptime backing_type: type) type {
    return struct { index: backing_type };
}

fn Literal(comptime backing_type: type) type {
    return struct { index: backing_type };
}

pub fn register(comptime backing_type: type, index: anytype) Register(backing_type) {
    return .{ .index = @intCast(index) };
}

pub fn constant(comptime backing_type: type, index: anytype) Constant(backing_type) {
    return .{ .index = @intCast(index) };
}

pub fn literal(comptime backing_type: type, index: anytype) Literal(backing_type) {
    return .{ .index = @intCast(index) };
}

pub const Instruction = union(enum(u8)) {
    const Self = @This();
    pub const Tag = std.meta.Tag(Self);
    pub const __note = "Register-stack based virtual machine instruction set";

    LoadConstant: struct {
        source: Register(u8),
        destination: Constant(u8),
        pub const __note = "Registers[destination] = Constants[source]";
    },
    LoadConstantLong: struct {
        source: Register(u24),
        destination: Constant(u24),
        pub const __note = "Registers[destination] = Constants[source]";
    },
    Copy: struct {
        source: Register(u8),
        destination: Register(u8),
        pub const __note = "Registers[destination] = Registers[source]";
    },

    Negate: struct {
        source: Register(u8),
        destination: Register(u8),
        pub const __note = "Registers[destination] = -Registers[source]";
    },
    Add: struct {
        source_0: Register(u8),
        source_1: Register(u8),
        destination: Register(u8),
        pub const __note = "Registers[destination] = Registers[source_0] + Registers[source_1]";
    },
    Subtract: struct {
        source_0: Register(u8),
        source_1: Register(u8),
        destination: Register(u8),
        pub const __note = "Registers[destination] = Registers[source_0] - Registers[source_1]";
    },
    Multiply: struct {
        source_0: Register(u8),
        source_1: Register(u8),
        destination: Register(u8),
        pub const __note = "Registers[destination] = Registers[source_0] * Registers[source_1]";
    },
    Divide: struct {
        source_0: Register(u8),
        source_1: Register(u8),
        destination: Register(u8),
        pub const __note = "Registers[destination] = Registers[source_0] / Registers[source_1]";
    },
    Print: struct {
        source: Register(u8),
        pub const __note = "Print(Registers[source])";
    },
    ExitVirtualMachine: struct {
        exit_code: Literal(u8),
        pub const __note = "Exit(exit_code)";
    },
};
