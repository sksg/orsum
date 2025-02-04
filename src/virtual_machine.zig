const std = @import("std");
const ir = @import("intermediate_representation.zig");
const disasemble = @import("disasemble.zig");

const InstructionSet = union(enum(u8)) {
    const Self = @This();
    pub const __note = "Register-stack based virtual machine instruction set";

    Load: struct {
        source: u8,
        destination: u8,
        pub const __note = "Registers[destination] = Constants[source]";
    },
    LoadLong: struct {
        source: u24,
        destination: u24,
        pub const __note = "Registers[destination] = Constants[source]";
    },
    Exit: struct {
        exit_code: u8,
        pub const __note = "Exit(exit_code)";
    },
};

const OperationType = std.meta.Tag(InstructionSet);
const AddressType = [*]const u8;
const IRChunk = ir.Chunk(InstructionSet, AddressType);

test "disasembly of single instructions" {
    std.debug.print("\nDisasembly of single instructions:\n{s}\n", .{disasemble.types_ruler(InstructionSet, "=")});
    std.debug.print("{s}\n", .{disasemble.instruction_type(InstructionSet, OperationType.Load)});
    std.debug.print("{s}\n", .{disasemble.instruction_type(InstructionSet, OperationType.LoadLong)});
    std.debug.print("{s}\n", .{disasemble.types_ruler(InstructionSet, "-")});
}

test "disasembly of instruction set" {
    std.debug.print("\nDisasembly of instruction set:\n{s}\n", .{disasemble.types_ruler(InstructionSet, "=")});
    std.debug.print("{s}\n", .{disasemble.instruction_set(InstructionSet)});
    std.debug.print("{s}\n", .{disasemble.types_ruler(InstructionSet, "-")});
}

test "disasembly of single instruction values" {
    std.debug.print("\nDisasembly of instruction values:\n{s}\n", .{disasemble.values_ruler(InstructionSet, "=")});
    std.debug.print("{s}\n", .{disasemble.instruction_value(InstructionSet, 42, OperationType.Load, .{ .source = 0, .destination = 0 })});
    std.debug.print("{s}\n", .{disasemble.instruction_value(InstructionSet, 42, OperationType.Load, .{ .source = 255, .destination = 255 })});
    std.debug.print("{s}\n", .{disasemble.instruction_value(InstructionSet, 43, OperationType.LoadLong, .{ .source = 0, .destination = 0 })});
    std.debug.print("{s}\n", .{disasemble.instruction_value(InstructionSet, 43, OperationType.LoadLong, .{ .source = 12345678, .destination = 12345678 })});
    std.debug.print("{s}\n", .{disasemble.values_ruler(InstructionSet, "-")});
}

test "disasembly of instruction value lists" {
    var list = std.ArrayList(InstructionSet).init(std.testing.allocator);
    defer list.deinit();

    for (0..10) |i| {
        _ = try list.append(.{ .Load = .{ .source = @intCast(i), .destination = @intCast(i) } });
    }
    for (0..10) |i| {
        _ = try list.append(.{ .LoadLong = .{ .source = @intCast(i * 255), .destination = @intCast(i * 255) } });
    }

    std.debug.print("\nDisasembly of instruction list:\n{s}\n", .{disasemble.values_ruler(InstructionSet, "=")});
    std.debug.print("{s}\n", .{disasemble.instruction_list(InstructionSet, 20, list.items)});
    std.debug.print("{s}\n", .{disasemble.values_ruler(InstructionSet, "-")});
}

test "Test disasembly" {
    const allocator = std.testing.allocator;

    const dummy_input = "dummy input";

    var chunk = IRChunk.init(allocator);
    defer chunk.deinit();

    const constant_index = try chunk.append_constant(.{ .u8 = 12 });

    for (0..300) |_| {
        _ = try chunk.append_constant(.{ .u8 = 34 });
    }

    const constant_index_long = try chunk.append_constant(.{ .u8 = 56 });

    try chunk.append_instruction(dummy_input.ptr[0..], .Load, .{ .source = @intCast(constant_index), .destination = 0 });
    try chunk.append_instruction(dummy_input.ptr[0..], .LoadLong, .{ .source = @intCast(constant_index_long), .destination = 0 });
    try chunk.append_instruction(dummy_input.ptr[6..], .Exit, .{ .exit_code = 0 });

    // chunk.print_disasembly();
    // chunk.print_disasembly_with_input(dummy_input);
}

pub fn VirtualMachine(comptime debug_mode: bool) type {
    return struct {
        const Self = @This();
        const DebugMode = debug_mode;
        chunk: *const IRChunk,
        instruction_cursor: usize,

        pub fn init(chunk: *const IRChunk) Self {
            return Self{
                .chunk = chunk,
                .instruction_cursor = 0,
            };
        }

        pub fn is_at_end(self: *Self) bool {
            return self.instruction_cursor >= self.chunk.bytecode.items.len;
        }

        pub fn interpret(self: *Self) u8 {
            if (DebugMode)
                std.debug.print("\nBegin interpretation:\n{s}\n", .{disasemble.values_ruler(InstructionSet, "=")});
            while (!self.is_at_end()) {
                const current_cursor = self.instruction_cursor;
                const operation = self.chunk.read_operation(&self.instruction_cursor);
                switch (operation) {
                    .Load => {
                        const operands = self.chunk.read_operands(.Load, &self.instruction_cursor);
                        if (DebugMode)
                            std.debug.print("{s}\n", .{disasemble.instruction_value(InstructionSet, current_cursor, .Load, operands)});
                    },
                    .LoadLong => {
                        const operands = self.chunk.read_operands(.LoadLong, &self.instruction_cursor);
                        if (DebugMode)
                            std.debug.print("{s}\n", .{disasemble.instruction_value(InstructionSet, current_cursor, .LoadLong, operands)});
                    },
                    .Exit => {
                        const operands = self.chunk.read_operands(.Exit, &self.instruction_cursor);
                        if (DebugMode) {
                            std.debug.print("{s}\n", .{disasemble.instruction_value(InstructionSet, current_cursor, .Exit, operands)});
                            std.debug.print("{s}\n", .{disasemble.values_ruler(InstructionSet, "-")});
                        }
                        return operands.exit_code;
                    },
                }
            }

            return 0;
        }
    };
}
test "test virtual machine" {
    const allocator = std.testing.allocator;

    var chunk = IRChunk.init(allocator);
    defer chunk.deinit();

    const constant_index = try chunk.append_constant(.{ .u8 = 12 });

    for (0..300) |_| {
        _ = try chunk.append_constant(.{ .u8 = 34 });
    }

    const constant_index_long = try chunk.append_constant(.{ .u8 = 56 });

    try chunk.append_instruction(null, .Load, .{ .source = @intCast(constant_index), .destination = 0 });
    try chunk.append_instruction(null, .LoadLong, .{ .source = @intCast(constant_index_long), .destination = 0 });
    try chunk.append_instruction(null, .Exit, .{ .exit_code = 0 });

    var instruction_list = std.ArrayList(InstructionSet).init(allocator);
    defer instruction_list.deinit();

    try chunk.unpack_into_instruction_list(&instruction_list);
    std.debug.print("\nDisasembly of instruction list:\n{s}\n", .{disasemble.values_ruler(InstructionSet, "=")});
    for (instruction_list.items, 0..) |instruction, index| {
        const operation: std.meta.Tag(InstructionSet) = @enumFromInt(@intFromEnum(instruction));
        switch (operation) {
            inline else => |op| {
                const operands = @field(instruction, @tagName(op));
                std.debug.print("{s}\n", .{disasemble.instruction_value(InstructionSet, index, op, operands)});
            },
        }
    }
    std.debug.print("{s}\n", .{disasemble.values_ruler(InstructionSet, "-")});

    var vm = VirtualMachine(true).init(&chunk);

    const exit_code = vm.interpret();

    std.debug.print("Intepreter has exited normally with code {}!\n", .{exit_code});
}
