const std = @import("std");
const ir = @import("intermediate_representation.zig");
const disasemble = @import("disasemble.zig");

pub fn VirtualMachine(comptime debug_mode: bool) type {
    return struct {
        const Self = @This();
        const DebugMode = debug_mode;
        register_stack: std.ArrayList(ir.Value),

        pub fn init(allocator: std.mem.Allocator) Self {
            if (DebugMode) {
                std.debug.print("Virtual machine based on instruction set {}:\n{s}\n", .{ ir.Instruction, disasemble.types_ruler(ir.Instruction, "=") });
                std.debug.print("{s}\n", .{disasemble.instruction_set(ir.Instruction)});
                std.debug.print("{s}\n\n", .{disasemble.types_ruler(ir.Instruction, "-")});
            }

            return Self{
                .register_stack = std.ArrayList(ir.Value).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.register_stack.deinit();
        }

        pub fn is_at_end(chunk: *const ir.Chunk, instruction_cursor: usize) bool {
            return instruction_cursor >= chunk.bytecode.items.len;
        }

        pub fn debug_trace_execution(chunk: *const ir.Chunk, current_cursor: usize) void {
            var debug_cursor = current_cursor;
            if (DebugMode) {
                const operation: ir.Instruction.Tag = chunk.read_operation(&debug_cursor);
                switch (operation) {
                    inline else => |op| {
                        const operands = chunk.read_operands(op, &debug_cursor);
                        std.debug.print("{s}\n", .{disasemble.instruction_value(ir.Instruction, current_cursor, op, operands)});
                    },
                }
            }
        }

        pub fn interpret(self: *Self, chunk: *const ir.Chunk) !u8 {
            var registers = try self.register_stack.addManyAsSlice(chunk.register_count);

            if (DebugMode)
                std.debug.print("{s}\n", .{disasemble.values_ruler(ir.Instruction, "=")});
            var instruction_cursor: usize = 0;
            while (!is_at_end(chunk, instruction_cursor)) {
                const current_cursor = instruction_cursor;
                debug_trace_execution(chunk, current_cursor);

                const operation: ir.Instruction.Tag = chunk.read_operation(&instruction_cursor);
                switch (operation) {
                    .LoadConstant => {
                        const operands = chunk.read_operands(.LoadConstant, &instruction_cursor);
                        registers[operands.destination.index] = chunk.constants.items[operands.source.index];
                    },
                    .Copy => {
                        const operands = chunk.read_operands(.Copy, &instruction_cursor);
                        registers[operands.destination.index] = registers[operands.source.index];
                    },
                    .Negate => {
                        const operands = chunk.read_operands(.Negate, &instruction_cursor);
                        registers[operands.destination.index] = registers[operands.source.index].negate();
                    },
                    .Add => {
                        const operands = chunk.read_operands(.Add, &instruction_cursor);
                        registers[operands.destination.index] = try registers[operands.source_0.index].add(registers[operands.source_1.index]);
                    },
                    .Subtract => {
                        const operands = chunk.read_operands(.Subtract, &instruction_cursor);
                        registers[operands.destination.index] = try registers[operands.source_0.index].subtract(registers[operands.source_1.index]);
                    },
                    .Multiply => {
                        const operands = chunk.read_operands(.Multiply, &instruction_cursor);
                        registers[operands.destination.index] = try registers[operands.source_0.index].multiply(registers[operands.source_1.index]);
                    },
                    .Divide => {
                        const operands = chunk.read_operands(.Divide, &instruction_cursor);
                        registers[operands.destination.index] = try registers[operands.source_0.index].divide(registers[operands.source_1.index]);
                    },
                    .Print => {
                        const operands = chunk.read_operands(.Print, &instruction_cursor);
                        std.debug.print("{}\n", .{registers[operands.source.index]});
                    },
                    .ExitVirtualMachine => {
                        const operands = chunk.read_operands(.ExitVirtualMachine, &instruction_cursor);
                        return operands.exit_code.index;
                    },
                }
            }

            return 0;
        }
    };
}
test "test virtual machine" {
    const allocator = std.testing.allocator;

    var chunk = ir.Chunk.init(allocator);
    defer chunk.deinit();

    const constants = .{ try chunk.append_constant(.{ .Integer = 3 }), try chunk.append_constant(.{ .Integer = 4 }) };
    const registers = .{ chunk.new_register(), chunk.new_register(), chunk.new_register() };

    try chunk.append_instruction(null, .LoadConstant, .{ .source = @intCast(constants[0]), .destination = @intCast(registers[0]) });
    try chunk.append_instruction(null, .LoadConstant, .{ .source = @intCast(constants[1]), .destination = @intCast(registers[1]) });
    try chunk.append_instruction(null, .Multiply, .{ .source_0 = @intCast(registers[0]), .source_1 = @intCast(registers[1]), .destination = @intCast(registers[2]) });
    try chunk.append_instruction(null, .Print, .{ .source = @intCast(registers[2]) });
    try chunk.append_instruction(null, .ExitVirtualMachine, .{ .exit_code = 0 });

    var instruction_list = std.ArrayList(ir.Instruction).init(allocator);
    defer instruction_list.deinit();

    try chunk.unpack_into_instruction_list(&instruction_list);
    std.debug.print("IR \"chunk\" disasembly:\n{s}\n", .{disasemble.values_ruler(ir.Instruction, "=")});
    for (instruction_list.items, 0..) |instruction, index| {
        const operation: std.meta.Tag(ir.Instruction) = @enumFromInt(@intFromEnum(instruction));
        switch (operation) {
            inline else => |op| {
                const operands = @field(instruction, @tagName(op));
                std.debug.print("{s}\n", .{disasemble.instruction_value(ir.Instruction, index, op, operands)});
            },
        }
    }
    std.debug.print("{s}\n\n", .{disasemble.values_ruler(ir.Instruction, "-")});

    var vm = VirtualMachine(true).init(allocator);
    defer vm.deinit();

    std.debug.print("Run virtual machine...\n", .{});
    const exit_code = try vm.interpret(&chunk);
    std.debug.print("Virtual machine has exited normally with exit-code {}!\n", .{exit_code});
}
