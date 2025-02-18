const std = @import("std");

pub const Value = @import("values.zig").Value;
pub const Address = @import("tokens.zig").Token.Address;
pub const Chunk = @import("chunks.zig").Chunk(@This());

fn Register(comptime backing_type: type) type {
    return struct {
        const Type = backing_type;
        const AccessorTag = enum { Read, Write };
        const Read = Accessor(.Read);
        const Write = Accessor(.Write);
        index: backing_type,

        pub fn Accessor(comptime tag: AccessorTag) type {
            return struct {
                const Tag = tag;
                const Type = backing_type;

                index: backing_type,

                const WithDebugInfo = struct {
                    accessor: Accessor(Tag),
                    registers: ?*[]Value,

                    pub fn format(with_info: WithDebugInfo, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                        if (Tag == .Read and with_info.registers != null)
                            try writer.print("{}(R{})", .{ with_info.registers.?[with_info.accessor.index], with_info.accessor.index })
                        else
                            try writer.print("R{}", .{with_info.accessor.index}); // The value is not neccesary with write-only access
                    }
                };

                pub fn with_debug_info(self: Accessor(Tag), registers: *[]Value) Accessor(Tag).WithDebugInfo {
                    return .{ .index = self.index, .registers = registers };
                }

                pub fn format(self: Accessor(Tag), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                    try writer.print("R{}", .{self.index});
                }
            };
        }

        pub fn read_access(self: Register(Type)) Accessor(.Read) {
            return .{ .index = self.index };
        }

        pub fn write_access(self: Register(Type)) Accessor(.Write) {
            return .{ .index = self.index };
        }

        pub fn format(self: Register(Type), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("R{}", .{self.index});
        }
    };
}

fn Constant(comptime backing_type: type) type {
    return struct {
        const Type = backing_type;
        index: backing_type,

        pub fn format(self: Constant(Type), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("C{}", .{self.index});
        }

        const WithDebugInfo = struct {
            index: backing_type,
            constants: *[]Value,

            pub fn format(self: WithDebugInfo, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                try writer.print("{}(C{})", .{ self.constants[self.index], self.index });
            }
        };

        pub fn with_debug_info(self: Constant(Type), constants: *[]Value) WithDebugInfo {
            return .{ .index = self.index, .constants = constants };
        }
    };
}

fn Literal(comptime backing_type: type) type {
    return struct {
        const Self = @This();
        index: backing_type,

        pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("{}", .{self.index});
        }
    };
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
        source: Constant(u8),
        destination: Register(u8).Write,
        pub const __note = "Registers[destination] = Constants[source]";
        pub const fmt = "{[destination]} = {[source]}";
    },
    Copy: struct {
        source: Register(u8).Read,
        destination: Register(u8).Write,
        pub const __note = "Registers[destination] = Registers[source]";
        pub const fmt = "{[destination]} = {[source]}";
    },

    Negate: struct {
        source: Register(u8).Read,
        destination: Register(u8).Write,
        pub const __note = "Registers[destination] = -Registers[source]";
        pub const fmt = "{[destination]} = -{[source]}";
    },
    Add: struct {
        source_0: Register(u8).Read,
        source_1: Register(u8).Read,
        destination: Register(u8).Write,
        pub const __note = "Registers[destination] = Registers[source_0] + Registers[source_1]";
        pub const fmt = "{[destination]} = {[source_0]} + {[source_1]}";
    },
    Subtract: struct {
        source_0: Register(u8).Read,
        source_1: Register(u8).Read,
        destination: Register(u8).Write,
        pub const __note = "Registers[destination] = Registers[source_0] - Registers[source_1]";
        pub const fmt = "{[destination]} = {[source_0]} - {[source_1]}";
    },
    Multiply: struct {
        source_0: Register(u8).Read,
        source_1: Register(u8).Read,
        destination: Register(u8).Write,
        pub const __note = "Registers[destination] = Registers[source_0] * Registers[source_1]";
        pub const fmt = "{[destination]} = {[source_0]} * {[source_1]}";
    },
    Divide: struct {
        source_0: Register(u8).Read,
        source_1: Register(u8).Read,
        destination: Register(u8).Write,
        pub const __note = "Registers[destination] = Registers[source_0] / Registers[source_1]";
        pub const fmt = "{[destination]} = {[source_0]} / {[source_1]}";
    },
    Print: struct {
        source: Register(u8).Read,
        pub const __note = "Print(Registers[source])";
        pub const fmt = "{[source]}";
    },
    ExitVirtualMachine: struct {
        exit_code: Literal(u8),
        pub const __note = "Exit(exit_code)";
        pub const fmt = "{[exit_code]}";
    },

    pub fn Operands(comptime tag: Tag) type {
        return @TypeOf(@field(@unionInit(Instruction, @tagName(tag), undefined), @tagName(tag)));
    }

    pub fn write_padded_tagname(comptime tag: Tag, writer: anytype) !void {
        const maximum_tagname_len = comptime blk: {
            var _maximum_tagname_len: usize = 0;
            for (@typeInfo(Instruction).Union.fields) |field| {
                const tagname_len = field.name.len;
                if (tagname_len > _maximum_tagname_len) {
                    _maximum_tagname_len = tagname_len;
                }
            }
            break :blk _maximum_tagname_len;
        };
        try writer.print("{s: >" ++ std.fmt.digits2(maximum_tagname_len) ++ "}", .{@tagName(tag)});
    }

    pub fn format(self: Instruction, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        const tag_at_runtime: Tag = @enumFromInt(@intFromEnum(self));
        switch (tag_at_runtime) {
            inline else => |tag| {
                try Instruction.write_padded_tagname(tag, writer);
                try writer.print("; ", .{});
                const operands = @field(self, @tagName(tag));
                try writer.print(@TypeOf(operands).fmt, operands);
            },
        }
    }
};

test "formatting of instructions" {
    const instructions = [_]Instruction{
        Instruction{ .LoadConstant = .{ .source = constant(u8, 1), .destination = register(u8, 0).write_access() } },
        Instruction{ .Copy = .{ .source = register(u8, 1).read_access(), .destination = register(u8, 2).write_access() } },
        Instruction{ .Negate = .{ .source = register(u8, 2).read_access(), .destination = register(u8, 3).write_access() } },
        Instruction{ .Add = .{ .source_0 = register(u8, 3).read_access(), .source_1 = register(u8, 4).read_access(), .destination = register(u8, 5).write_access() } },
        Instruction{ .Subtract = .{ .source_0 = register(u8, 5).read_access(), .source_1 = register(u8, 6).read_access(), .destination = register(u8, 7).write_access() } },
        Instruction{ .Multiply = .{ .source_0 = register(u8, 7).read_access(), .source_1 = register(u8, 8).read_access(), .destination = register(u8, 9).write_access() } },
        Instruction{ .Divide = .{ .source_0 = register(u8, 9).read_access(), .source_1 = register(u8, 10).read_access(), .destination = register(u8, 11).write_access() } },
        Instruction{ .Print = .{ .source = register(u8, 11).read_access() } },
        Instruction{ .ExitVirtualMachine = .{ .exit_code = literal(u8, 0) } },
    };

    for (instructions) |instruction| {
        std.debug.print("{}\n", .{instruction});
    }
}
