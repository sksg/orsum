const std = @import("std");
const ir = @import("intermediate_representation.zig");
const values = @import("values.zig");
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
    Copy: struct {
        source: u8,
        destination: u8,
        pub const __note = "Registers[destination] = Registers[source]";
    },

    Negate: struct {
        source: u8,
        destination: u8,
        pub const __note = "Registers[destination] = -Registers[source]";
    },
    Add: struct {
        source_0: u8,
        source_1: u8,
        destination: u8,
        pub const __note = "Registers[destination] = Registers[source_0] + Registers[source_1]";
    },
    Subtract: struct {
        source_0: u8,
        source_1: u8,
        destination: u8,
        pub const __note = "Registers[destination] = Registers[source_0] - Registers[source_1]";
    },
    Multiply: struct {
        source_0: u8,
        source_1: u8,
        destination: u8,
        pub const __note = "Registers[destination] = Registers[source_0] * Registers[source_1]";
    },
    Divide: struct {
        source_0: u8,
        source_1: u8,
        destination: u8,
        pub const __note = "Registers[destination] = Registers[source_0] / Registers[source_1]";
    },
    Print: struct {
        source: u8,
        pub const __note = "Print(Registers[source])";
    },
    ExitVirtualMachine: struct {
        exit_code: u8,
        pub const __note = "Exit(exit_code)";
    },
};

pub const OperationType = std.meta.Tag(InstructionSet);
pub const ValueType = values.ValueType;
pub const AddressType = [*]const u8;
pub const IRChunk = ir.Chunk(InstructionSet, ValueType, AddressType);

pub fn VirtualMachine(comptime debug_mode: bool) type {
    return struct {
        const Self = @This();
        const DebugMode = debug_mode;
        register_stack: std.ArrayList(ValueType),

        pub fn init(allocator: std.mem.Allocator) Self {
            if (DebugMode) {
                std.debug.print("Virtual machine based on instruction set {}:\n{s}\n", .{ InstructionSet, disasemble.types_ruler(InstructionSet, "=") });
                std.debug.print("{s}\n", .{disasemble.instruction_set(InstructionSet)});
                std.debug.print("{s}\n\n", .{disasemble.types_ruler(InstructionSet, "-")});
            }

            return Self{
                .register_stack = std.ArrayList(ValueType).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.register_stack.deinit();
        }

        pub fn is_at_end(chunk: *const IRChunk, instruction_cursor: usize) bool {
            return instruction_cursor >= chunk.bytecode.items.len;
        }

        pub fn debug_trace_execution(chunk: *const IRChunk, current_cursor: usize) void {
            var debug_cursor = current_cursor;
            if (DebugMode) {
                const operation: OperationType = chunk.read_operation(&debug_cursor);
                switch (operation) {
                    inline else => |op| {
                        const operands = chunk.read_operands(op, &debug_cursor);
                        std.debug.print("{s}\n", .{disasemble.instruction_value(InstructionSet, current_cursor, op, operands)});
                    },
                }
            }
        }

        pub fn interpret(self: *Self, chunk: *const IRChunk) !u8 {
            var registers = try self.register_stack.addManyAsSlice(chunk.register_count);

            if (DebugMode)
                std.debug.print("{s}\n", .{disasemble.values_ruler(InstructionSet, "=")});
            var instruction_cursor: usize = 0;
            while (!is_at_end(chunk, instruction_cursor)) {
                const current_cursor = instruction_cursor;
                debug_trace_execution(chunk, current_cursor);

                const operation: OperationType = chunk.read_operation(&instruction_cursor);
                switch (operation) {
                    .LoadConstant => {
                        const operands = chunk.read_operands(.LoadConstant, &instruction_cursor);
                        registers[operands.destination] = chunk.constants.items[operands.source];
                    },
                    .LoadConstantLong => {
                        const operands = chunk.read_operands(.LoadConstantLong, &instruction_cursor);
                        registers[operands.destination] = chunk.constants.items[operands.source];
                    },
                    .Copy => {
                        const operands = chunk.read_operands(.Copy, &instruction_cursor);
                        registers[operands.destination] = registers[operands.source];
                    },
                    .Negate => {
                        const operands = chunk.read_operands(.Negate, &instruction_cursor);
                        registers[operands.destination] = registers[operands.source].negate();
                    },
                    .Add => {
                        const operands = chunk.read_operands(.Add, &instruction_cursor);
                        registers[operands.destination] = try registers[operands.source_0].add(registers[operands.source_1]);
                    },
                    .Subtract => {
                        const operands = chunk.read_operands(.Subtract, &instruction_cursor);
                        registers[operands.destination] = try registers[operands.source_0].subtract(registers[operands.source_1]);
                    },
                    .Multiply => {
                        const operands = chunk.read_operands(.Multiply, &instruction_cursor);
                        registers[operands.destination] = try registers[operands.source_0].multiply(registers[operands.source_1]);
                    },
                    .Divide => {
                        const operands = chunk.read_operands(.Divide, &instruction_cursor);
                        registers[operands.destination] = try registers[operands.source_0].divide(registers[operands.source_1]);
                    },
                    .Print => {
                        const operands = chunk.read_operands(.Print, &instruction_cursor);
                        std.debug.print("{}\n", .{registers[operands.source]});
                    },
                    .ExitVirtualMachine => {
                        const operands = chunk.read_operands(.ExitVirtualMachine, &instruction_cursor);
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

    const constants = .{ try chunk.append_constant(.{ .Integer = 3 }), try chunk.append_constant(.{ .Integer = 4 }) };
    const register = .{ chunk.new_register(), chunk.new_register(), chunk.new_register() };

    try chunk.append_instruction(null, .LoadConstant, .{ .source = @intCast(constants[0]), .destination = @intCast(register[0]) });
    try chunk.append_instruction(null, .LoadConstant, .{ .source = @intCast(constants[1]), .destination = @intCast(register[1]) });
    try chunk.append_instruction(null, .Multiply, .{ .source_0 = @intCast(register[0]), .source_1 = @intCast(register[1]), .destination = @intCast(register[2]) });
    try chunk.append_instruction(null, .Print, .{ .source = @intCast(register[2]) });
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
