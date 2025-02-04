const std = @import("std");
const ir = @import("intermediate_representation.zig");
const disasemble = @import("disasemble.zig");

const InstructionSet = union(enum(u8)) {
    const Self = @This();
    pub const __note = "Register-stack based virtual machine instruction set";

    LoadConstant: struct {
        source: u8,
        destination: u8,
        pub const __note = "Registers[destination] = Constants[source]";
    },
    LoadConstantLong: struct {
        source: u24,
        destination: u24,
        pub const __note = "Registers[destination] = Constants[source]";
    },
    ExitVirtualMachine: struct {
        exit_code: u8,
        pub const __note = "Exit(exit_code)";
    },
};

const OperationType = std.meta.Tag(InstructionSet);
const AddressType = [*]const u8;
const IRChunk = ir.Chunk(InstructionSet, AddressType);

pub fn VirtualMachine(comptime debug_mode: bool) type {
    return struct {
        const Self = @This();
        const DebugMode = debug_mode;
        register_stack: std.ArrayList(IRChunk.ValueType),

        pub fn init(allocator: std.mem.Allocator) Self {
            if (DebugMode) {
                std.debug.print("Virtual machine based on instruction set {}:\n{s}\n", .{ InstructionSet, disasemble.types_ruler(InstructionSet, "=") });
                std.debug.print("{s}\n", .{disasemble.instruction_set(InstructionSet)});
                std.debug.print("{s}\n\n", .{disasemble.types_ruler(InstructionSet, "-")});
            }

            return Self{
                .register_stack = std.ArrayList(IRChunk.ValueType).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.register_stack.deinit();
        }

        pub fn is_at_end(chunk: *const IRChunk, instruction_cursor: usize) bool {
            return instruction_cursor >= chunk.bytecode.items.len;
        }

        pub fn interpret(self: *Self, chunk: *const IRChunk) !u8 {
            var registers = try self.register_stack.addManyAsSlice(chunk.register_count);

            if (DebugMode)
                std.debug.print("{s}\n", .{disasemble.values_ruler(InstructionSet, "=")});
            var instruction_cursor: usize = 0;
            while (!is_at_end(chunk, instruction_cursor)) {
                const current_cursor = instruction_cursor;
                const operation: OperationType = chunk.read_operation(&instruction_cursor);
                switch (operation) {
                    .LoadConstant => {
                        const operands = chunk.read_operands(.LoadConstant, &instruction_cursor);
                        if (DebugMode)
                            std.debug.print("{s}\n", .{disasemble.instruction_value(InstructionSet, current_cursor, .LoadConstant, operands)});
                        registers[operands.destination] = chunk.constants.items[operands.source];
                    },
                    .LoadConstantLong => {
                        const operands = chunk.read_operands(.LoadConstantLong, &instruction_cursor);
                        if (DebugMode)
                            std.debug.print("{s}\n", .{disasemble.instruction_value(InstructionSet, current_cursor, .LoadConstantLong, operands)});
                        registers[operands.destination] = chunk.constants.items[operands.source];
                    },
                    .ExitVirtualMachine => {
                        const operands = chunk.read_operands(.ExitVirtualMachine, &instruction_cursor);
                        if (DebugMode) {
                            std.debug.print("{s}\n", .{disasemble.instruction_value(InstructionSet, current_cursor, .ExitVirtualMachine, operands)});
                            std.debug.print("{s}\n", .{disasemble.values_ruler(InstructionSet, "=")});
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

    const register_0 = chunk.new_register();
    const register_1 = chunk.new_register();

    try chunk.append_instruction(null, .LoadConstant, .{ .source = @intCast(constant_index), .destination = @intCast(register_0) });
    try chunk.append_instruction(null, .LoadConstantLong, .{ .source = @intCast(constant_index_long), .destination = @intCast(register_1) });
    try chunk.append_instruction(null, .ExitVirtualMachine, .{ .exit_code = 0 });

    var instruction_list = std.ArrayList(InstructionSet).init(allocator);
    defer instruction_list.deinit();

    try chunk.unpack_into_instruction_list(&instruction_list);
    std.debug.print("IR \"chunk\" disasembly:\n{s}\n", .{disasemble.values_ruler(InstructionSet, "=")});
    for (instruction_list.items, 0..) |instruction, index| {
        const operation: std.meta.Tag(InstructionSet) = @enumFromInt(@intFromEnum(instruction));
        switch (operation) {
            inline else => |op| {
                const operands = @field(instruction, @tagName(op));
                std.debug.print("{s}\n", .{disasemble.instruction_value(InstructionSet, index, op, operands)});
            },
        }
    }
    std.debug.print("{s}\n\n", .{disasemble.values_ruler(InstructionSet, "-")});

    var vm = VirtualMachine(true).init(allocator);
    defer vm.deinit();

    std.debug.print("Run virtual machine...\n", .{});
    const exit_code = try vm.interpret(&chunk);
    std.debug.print("Virtual machine has exited normally with exit-code {}!\n", .{exit_code});
}
