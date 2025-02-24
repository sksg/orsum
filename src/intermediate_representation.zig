const std = @import("std");

pub const Value = @import("values.zig").Value;
pub const Address = @import("tokens.zig").Token.Address;

pub fn Register(comptime backing_type: type) type {
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
                    registers: ?[]const Value,

                    pub fn format(with_info: WithDebugInfo, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                        if (Tag == .Read and with_info.registers != null)
                            try writer.print("{}{{R{}}}", .{ with_info.registers.?[with_info.accessor.index], with_info.accessor.index })
                        else
                            try writer.print("R{}", .{with_info.accessor.index}); // The value is not neccesary with write-only access
                    }
                };

                pub fn with_debug_info(self: Accessor(Tag), registers: ?[]const Value) Accessor(Tag).WithDebugInfo {
                    return .{ .accessor = self, .registers = registers };
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

pub fn Constant(comptime backing_type: type) type {
    return struct {
        const Type = backing_type;
        index: backing_type,

        pub fn format(self: Constant(Type), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("C{}", .{self.index});
        }

        const WithDebugInfo = struct {
            index: backing_type,
            constants: ?[]const Value,

            pub fn format(with_info: WithDebugInfo, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                if (with_info.constants != null)
                    try writer.print("{}{{C{}}}", .{ with_info.constants.?[with_info.index], with_info.index })
                else
                    try writer.print("C{}", .{with_info.index}); // The value is not neccesary with write-only access
            }
        };

        pub fn with_debug_info(self: Constant(Type), constants: ?[]const Value) WithDebugInfo {
            return .{ .index = self.index, .constants = constants };
        }
    };
}

pub fn Literal(comptime backing_type: type) type {
    return struct {
        const Self = @This();
        const Type = backing_type;
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

pub fn OperandWithDebugInfo(comptime Operand: type) type {
    const Type: type = Operand.Type;
    if (Operand == Register(Type).Accessor(.Read)) {
        return Register(Type).Accessor(.Read).WithDebugInfo;
    } else if (Operand == Register(Type).Accessor(.Write)) {
        return Register(Type).Accessor(.Write).WithDebugInfo;
    } else if (Operand == Constant(Type)) {
        return Constant(Type).WithDebugInfo;
    } else if (Operand == Literal(Type)) {
        return Literal(Type);
    } else {
        @compileError("Unsupported operand type");
    }
}

pub fn operand_with_debug_info(operand: anytype, registers: ?[]const Value, constants: ?[]const Value) OperandWithDebugInfo(@TypeOf(operand)) {
    const Operand: type = @TypeOf(operand);
    const Type: type = Operand.Type;
    if (Operand == Register(Type).Accessor(.Read)) {
        return operand.with_debug_info(registers);
    } else if (Operand == Register(Type).Accessor(.Write)) {
        return operand.with_debug_info(registers);
    } else if (Operand == Constant(Type)) {
        return operand.with_debug_info(constants);
    } else if (Operand == Literal(Type)) {
        return operand;
    } else {
        @compileError("Unsupported operand type");
    }
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
        pub const fmt = "Print({[source]})";
    },
    ExitVirtualMachine: struct {
        exit_code: Literal(u8),
        pub const __note = "Exit(exit_code)";
        pub const fmt = "Exit({[exit_code]})";
    },

    pub fn Operands(comptime tag: Tag) type {
        return @TypeOf(@field(@unionInit(Instruction, @tagName(tag), undefined), @tagName(tag)));
    }

    pub fn init(comptime tag: Tag, operands: Operands(tag)) Self {
        return @unionInit(Self, @tagName(tag), operands);
    }

    pub fn init_with_debug_info(comptime tag: Tag, operands: Operands(tag), registers: ?[]const Value, constants: ?[]const Value) WithDebugInfo {
        return init(tag, operands).with_debug_info(registers, constants);
    }

    pub fn OperandsWithDebugInfo(comptime tag: Tag) type {
        const operands_info = @typeInfo(Operands(tag)).Struct;

        var operand_fields_with_info: [operands_info.fields.len]std.builtin.Type.StructField = undefined;
        for (operands_info.fields, 0..) |field, index| {
            operand_fields_with_info[index] = .{
                .name = field.name,
                .type = OperandWithDebugInfo(field.type),
                .default_value = field.default_value,
                .is_comptime = field.is_comptime,
                .alignment = field.alignment,
            };
        }
        return @Type(.{
            .Struct = .{
                .layout = .auto,
                .fields = &operand_fields_with_info,
                .decls = &[_]std.builtin.Type.Declaration{},
                .is_tuple = false,
            },
        });
    }

    pub fn operands_with_debug_info(comptime tag: Tag, operands: anytype, registers: ?[]const Value, constants: ?[]const Value) OperandsWithDebugInfo(tag) {
        var operands_with_info: OperandsWithDebugInfo(tag) = undefined;
        inline for (@typeInfo(OperandsWithDebugInfo(tag)).Struct.fields) |field| {
            @field(operands_with_info, field.name) = operand_with_debug_info(@field(operands, field.name), registers, constants);
        }
        return operands_with_info;
    }

    const FORMAT_PADDING_LEN = 26;

    pub fn format(self: Instruction, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        const tag_at_runtime: Tag = @enumFromInt(@intFromEnum(self));
        switch (tag_at_runtime) {
            inline else => |tag| {
                const operands = @field(self, @tagName(tag));
                var len = std.fmt.count(@TypeOf(operands).fmt, operands);
                try writer.print(@TypeOf(operands).fmt, operands);
                while (len < FORMAT_PADDING_LEN) {
                    _ = try writer.write(" ");
                    len += 1;
                }
                try writer.print("  ;; .{s}", .{@tagName(tag)});
            },
        }
    }

    const WithDebugInfo = struct {
        instruction: Instruction,
        registers: ?[]const Value,
        constants: ?[]const Value,

        pub fn format(with_info: WithDebugInfo, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            const tag_at_runtime: Tag = @enumFromInt(@intFromEnum(with_info.instruction));
            switch (tag_at_runtime) {
                inline else => |tag| {
                    const operands = @field(with_info.instruction, @tagName(tag));
                    const operands_with_info = operands_with_debug_info(tag, operands, with_info.registers, with_info.constants);
                    var len = std.fmt.count(@TypeOf(operands).fmt, operands_with_info);
                    try writer.print(@TypeOf(operands).fmt, operands_with_info);
                    while (len < FORMAT_PADDING_LEN) {
                        _ = try writer.write(" ");
                        len += 1;
                    }
                    try writer.print("  ;; .{s}", .{@tagName(tag)});
                },
            }
        }
    };

    pub fn with_debug_info(self: Instruction, registers: ?[]const Value, constants: ?[]const Value) WithDebugInfo {
        return .{ .instruction = self, .registers = registers, .constants = constants };
    }
};

test "formatting of instructions" {
    const constants = [_]Value{ Value{ .Integer = 1 }, Value{ .FloatingPoint = 3.14 } };
    const registers = [_]Value{
        Value{ .Integer = 1 },
        Value{ .Integer = 2 },
        Value{ .Integer = 3 },
        Value{ .Integer = 4 },
        Value{ .Integer = 5 },
        Value{ .Integer = 6 },
        Value{ .Integer = 7 },
        Value{ .Integer = 8 },
        Value{ .Integer = 9 },
        Value{ .Integer = 10 },
        Value{ .Integer = 11 },
        Value{ .Integer = 12 },
    };

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
        std.debug.print("| {}\n", .{instruction});
    }
    for (instructions) |instruction| {
        const with_register_info = instruction.with_debug_info(&registers, null);
        std.debug.print("| {}\n", .{with_register_info});
    }
    for (instructions) |instruction| {
        const with_constants_info = instruction.with_debug_info(null, &constants);
        std.debug.print("| {}\n", .{with_constants_info});
    }
    for (instructions) |instruction| {
        const with_both_info = instruction.with_debug_info(&registers, &constants);
        std.debug.print("| {}\n", .{with_both_info});
    }
}

pub const Chunk = struct {
    const Self = @This();
    pub fn OperandType(comptime operation: Instruction.Tag) type {
        return @TypeOf(@field(@unionInit(Instruction, @tagName(operation), undefined), @tagName(operation)));
    }

    bytecode: std.ArrayList(u8),
    constants: std.ArrayList(Value),
    register_count: usize,
    debug_info: RunLengthEncodedArrayList(Address),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .bytecode = std.ArrayList(u8).init(allocator),
            .constants = std.ArrayList(Value).init(allocator),
            .register_count = 0,
            .debug_info = RunLengthEncodedArrayList(Address).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.bytecode.deinit();
        self.constants.deinit();
        self.debug_info.deinit();
    }

    pub fn new_register(self: *Self) Register(u8) {
        const _register = register(u8, self.register_count);
        self.register_count += 1;
        return _register;
    }

    pub fn append_constant(self: *Self, value: Value) !Constant(u8) {
        try self.constants.append(value);
        return constant(u8, self.constants.items.len - 1);
    }

    pub fn append_instruction(self: *Self, address: ?Address, comptime operation: Instruction.Tag, operands: Self.OperandType(operation)) !void {
        // A single operation is just appended
        try self.bytecode.append(@intFromEnum(operation));
        if (address) |addr| try self.debug_info.append(addr);

        inline for (@typeInfo(@TypeOf(operands)).Struct.fields) |field| {
            const operand = @field(operands, field.name).index;
            if (@bitSizeOf(@TypeOf(operand)) >= 8)
                try self.bytecode.append(@intCast((operand >> 0) & 0xFF));
            if (@bitSizeOf(@TypeOf(operand)) >= 16)
                try self.bytecode.append(@intCast((operand >> 8) & 0xFF));
            if (@bitSizeOf(@TypeOf(operand)) >= 24)
                try self.bytecode.append(@intCast((operand >> 16) & 0xFF));
            if (@bitSizeOf(@TypeOf(operand)) >= 32)
                try self.bytecode.append(@intCast((operand >> 24) & 0xFF));
            if (@bitSizeOf(@TypeOf(operand)) >= 40)
                try self.bytecode.append(@intCast((operand >> 32) & 0xFF));
            if (@bitSizeOf(@TypeOf(operand)) >= 48)
                try self.bytecode.append(@intCast((operand >> 40) & 0xFF));
            if (@bitSizeOf(@TypeOf(operand)) >= 56)
                try self.bytecode.append(@intCast((operand >> 48) & 0xFF));
            if (@bitSizeOf(@TypeOf(operand)) >= 64)
                try self.bytecode.append(@intCast((operand >> 56) & 0xFF));

            if (address) |addr| try self.debug_info.append(addr);
        }
    }

    pub fn read_operation(self: Self, cursor: *usize) Instruction.Tag {
        const operation: Instruction.Tag = @enumFromInt(self.bytecode.items[cursor.*]);
        cursor.* += 1;
        return operation;
    }

    pub fn read_operand(self: Self, comptime operand_type: type, cursor: *usize) operand_type {
        var operand: operand_type = undefined;
        if (@bitSizeOf(operand_type) >= 8) {
            operand = @as(operand_type, self.bytecode.items[cursor.*]) << 0;
            cursor.* += 1;
        }
        if (@bitSizeOf(operand_type) >= 16) {
            operand += @as(operand_type, self.bytecode.items[cursor.*]) << 8;
            cursor.* += 1;
        }
        if (@bitSizeOf(operand_type) >= 24) {
            operand += @as(operand_type, self.bytecode.items[cursor.*]) << 16;
            cursor.* += 1;
        }
        if (@bitSizeOf(operand_type) >= 32) {
            operand += @as(operand_type, self.bytecode.items[cursor.*]) << 24;
            cursor.* += 1;
        }
        if (@bitSizeOf(operand_type) >= 40) {
            operand += @as(operand_type, self.bytecode.items[cursor.*]) << 32;
            cursor.* += 1;
        }
        if (@bitSizeOf(operand_type) >= 48) {
            operand += @as(operand_type, self.bytecode.items[cursor.*]) << 40;
            cursor.* += 1;
        }
        if (@bitSizeOf(operand_type) >= 56) {
            operand += @as(operand_type, self.bytecode.items[cursor.*]) << 48;
            cursor.* += 1;
        }
        if (@bitSizeOf(operand_type) >= 64) {
            operand += @as(operand_type, self.bytecode.items[cursor.*]) << 56;
            cursor.* += 1;
        }

        return operand;
    }

    pub fn read_operands(self: Self, comptime operation: Instruction.Tag, cursor: *usize) OperandType(operation) {
        var operands: OperandType(operation) = undefined;
        inline for (@typeInfo(OperandType(operation)).Struct.fields) |field| {
            const backing_type = @typeInfo(field.type).Struct.fields[0].type;
            @field(operands, field.name) = .{ .index = self.read_operand(backing_type, cursor) };
        }
        return operands;
    }

    pub fn read_instruction(self: Self, cursor: *usize) Instruction {
        const operation = self.read_operation(cursor);
        switch (operation) {
            inline else => |op| {
                var operands: OperandType(op) = undefined;
                inline for (@typeInfo(OperandType(op)).Struct.fields) |field| {
                    @field(operands, field.name) = self.read_operand(field.type, cursor);
                }
                return @unionInit(Instruction, @tagName(op), operands);
            },
        }
    }

    pub fn unpack_into_instruction_list(self: Self, instruction_list: *std.ArrayList(Instruction)) !void {
        var cursor: usize = 0;
        while (cursor < self.bytecode.items.len) {
            try instruction_list.append(self.read_instruction(&cursor));
        }
    }
};

fn RunLengthEncodedArrayList(T: type) type {
    return struct {
        encoded_data: std.ArrayList(entry_type), // Run-length encoding

        const item_type = T;
        const entry_type = struct { item: item_type, count: usize };
        const Self = RunLengthEncodedArrayList(item_type);

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .encoded_data = std.ArrayList(entry_type).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.encoded_data.deinit();
        }

        pub fn append(self: *Self, item: item_type) !void {
            // Test current item to see if it is the same as this new one
            if (self.encoded_data.items.len > 0) {
                var current = &self.encoded_data.items[self.encoded_data.items.len - 1];
                if (current.item == item) {
                    // If it is the same, increment the length
                    current.count += 1;
                    return;
                }
            }

            // Else we need to append a new Address
            try self.encoded_data.append(.{ .item = item, .count = 1 });
        }

        pub fn read_at(self: *const Self, item_index: usize) item_type {
            var count: usize = 0;
            for (self.encoded_data.items) |entry| {
                count += entry.count;
                if (count > item_index)
                    return entry.item;
            }

            unreachable;
        }
    };
}
