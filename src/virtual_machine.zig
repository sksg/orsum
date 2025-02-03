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

const VirtualMachine = struct {
    chunk: *const IRChunk,
    instruction_cursor: usize,

    pub fn init(chunk: *const IRChunk) VirtualMachine {
        return VirtualMachine{
            .chunk = chunk,
            .instruction_cursor = 0,
        };
    }

    pub fn read_operation(self: *VirtualMachine) OperationType {
        const operation: OperationType = @enumFromInt(self.chunk.bytecode.items[self.instruction_cursor]);
        self.instruction_cursor += 1;
        return operation;
    }

    pub fn read_operand_u8(self: *VirtualMachine) u8 {
        const operand = self.chunk.bytecode.items[self.instruction_cursor];
        self.instruction_cursor += 1;
        return operand;
    }

    pub fn read_operand_u24(self: *VirtualMachine) u24 {
        const operand_low: u24 = self.chunk.bytecode.items[self.instruction_cursor];
        self.instruction_cursor += 1;
        const operand_mid: u24 = self.chunk.bytecode.items[self.instruction_cursor];
        self.instruction_cursor += 1;
        const operand_high: u24 = self.chunk.bytecode.items[self.instruction_cursor];
        self.instruction_cursor += 1;
        return operand_low + (operand_mid << 8) + (operand_high << 16);
    }

    pub fn is_at_end(self: *VirtualMachine) bool {
        return self.instruction_cursor >= self.chunk.bytecode.items.len;
    }

    pub fn interpret(self: *VirtualMachine) u8 {
        while (!self.is_at_end()) {
            const operation = self.read_operation();
            switch (operation) {
                .Load => std.debug.print("Registers[{1}] = Constants[{0}]\n", .{ self.read_operand_u8(), self.read_operand_u8() }),
                .LoadLong => std.debug.print("Registers[{1}] = Constants[{0}]\n", .{ self.read_operand_u24(), self.read_operand_u24() }),
                .Exit => return self.read_operand_u8(),
            }
        }

        return 0;
    }
};

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

    // chunk.print_disasembly();

    var vm = VirtualMachine.init(&chunk);

    const exit_code = vm.interpret();

    std.debug.print("Exit code: {}\n", .{exit_code});
}
