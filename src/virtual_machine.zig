const std = @import("std");
const ir = @import("intermediate_representation.zig");
const syntax = @import("syntax.zig");

pub const VirtualMachineTracing = packed struct {
    execution: bool = false,
    stack: bool = false,
    with_input: bool = false,

    pub fn any(self: VirtualMachineTracing) bool {
        return self.execution or self.stack or self.with_input;
    }
};

pub const trace_execution = VirtualMachineTracing{ .execution = true };
pub const trace_execution_and_tack = VirtualMachineTracing{ .execution = true, .stack = true };
pub const trace_execution_with_input = VirtualMachineTracing{ .execution = true, .with_input = true };
pub const trace_all = VirtualMachineTracing{ .execution = true, .stack = true, .with_input = true };
pub const no_trace = VirtualMachineTracing{};

pub fn VirtualMachine(comptime tracing_mode: VirtualMachineTracing) type {
    return struct {
        const Self = @This();
        const Trace = tracing_mode;
        register_stack: std.ArrayList(ir.Value),
        input: []const u8,

        pub fn init(allocator: std.mem.Allocator, input: []const u8) Self {
            return Self{
                .register_stack = std.ArrayList(ir.Value).init(allocator),
                .input = input,
            };
        }

        pub fn deinit(self: *Self) void {
            self.register_stack.deinit();
        }

        pub fn is_at_end(chunk: *const ir.Chunk, instruction_cursor: usize) bool {
            return instruction_cursor >= chunk.bytecode.items.len;
        }

        pub fn debug_trace_execution(self: Self, chunk: *const ir.Chunk, current_cursor: usize) void {
            if (Trace.with_input) {
                const debug_address = chunk.debug_info.read_at(current_cursor);
                const debug_token = syntax.Token.init_from_address(self.input, debug_address).with_debug_info(self.input);
                std.debug.print("VM -- {s}\nVM -- ", .{debug_token.source_line()});
                debug_token.write_annotation_line(std.io.getStdErr().writer(), " ") catch unreachable;
                switch (debug_token.token.tag) {
                    inline else => |tag| std.debug.print("Token.{s}\n", .{@tagName(tag)}),
                }
            }
            if (Trace.execution) {
                var debug_cursor = current_cursor;
                const operation: ir.Instruction.Tag = chunk.read_operation(&debug_cursor);
                switch (operation) {
                    inline else => |op| {
                        const operands = chunk.read_operands(op, &debug_cursor);
                        const with_info = ir.Instruction.init_with_debug_info(op, operands, self.register_stack.items, chunk.constants.items);
                        std.debug.print("VM -- Exec: ({d:0>4}) :: {}\n", .{ current_cursor, with_info });
                    },
                }
            }
        }

        pub fn interpret(self: *Self, chunk: *const ir.Chunk) !u8 {
            var registers = try self.register_stack.addManyAsSlice(chunk.register_count);

            if (Trace.any())
                std.debug.print("VM -- ======\n", .{});
            var instruction_cursor: usize = 0;
            while (!is_at_end(chunk, instruction_cursor)) {
                const current_cursor = instruction_cursor;
                self.debug_trace_execution(chunk, current_cursor);

                const operation: ir.Instruction.Tag = chunk.read_operation(&instruction_cursor);
                switch (operation) {
                    .LoadConstant => {
                        const operands = chunk.read_operands(.LoadConstant, &instruction_cursor);
                        set_register(registers, operands.destination, chunk.constants.items[operands.source.index]);
                    },
                    .Copy => {
                        const operands = chunk.read_operands(.Copy, &instruction_cursor);
                        set_register(registers, operands.destination, registers[operands.source.index]);
                    },
                    .Not => {
                        const operands = chunk.read_operands(.Negate, &instruction_cursor);
                        set_register(registers, operands.destination, try registers[operands.source.index].not());
                    },
                    .Negate => {
                        const operands = chunk.read_operands(.Negate, &instruction_cursor);
                        set_register(registers, operands.destination, try registers[operands.source.index].negate());
                    },
                    .Add => {
                        const operands = chunk.read_operands(.Add, &instruction_cursor);
                        set_register(registers, operands.destination, try registers[operands.source_0.index].add(registers[operands.source_1.index]));
                    },
                    .Subtract => {
                        const operands = chunk.read_operands(.Subtract, &instruction_cursor);
                        set_register(registers, operands.destination, try registers[operands.source_0.index].subtract(registers[operands.source_1.index]));
                    },
                    .Multiply => {
                        const operands = chunk.read_operands(.Multiply, &instruction_cursor);
                        set_register(registers, operands.destination, try registers[operands.source_0.index].multiply(registers[operands.source_1.index]));
                    },
                    .Divide => {
                        const operands = chunk.read_operands(.Divide, &instruction_cursor);
                        set_register(registers, operands.destination, try registers[operands.source_0.index].divide(registers[operands.source_1.index]));
                    },
                    .Equal => {
                        const operands = chunk.read_operands(.Equal, &instruction_cursor);
                        set_register(registers, operands.destination, try registers[operands.source_0.index].equal(registers[operands.source_1.index]));
                    },
                    .NotEqual => {
                        const operands = chunk.read_operands(.NotEqual, &instruction_cursor);
                        set_register(registers, operands.destination, try registers[operands.source_0.index].not_equal(registers[operands.source_1.index]));
                    },
                    .GreaterThan => {
                        const operands = chunk.read_operands(.GreaterThan, &instruction_cursor);
                        set_register(registers, operands.destination, try registers[operands.source_0.index].greater_than(registers[operands.source_1.index]));
                    },
                    .GreaterThanOrEqual => {
                        const operands = chunk.read_operands(.GreaterThanOrEqual, &instruction_cursor);
                        set_register(registers, operands.destination, try registers[operands.source_0.index].greater_than_or_equal(registers[operands.source_1.index]));
                    },
                    .LessThan => {
                        const operands = chunk.read_operands(.LessThan, &instruction_cursor);
                        set_register(registers, operands.destination, try registers[operands.source_0.index].less_than(registers[operands.source_1.index]));
                    },
                    .LessThanOrEqual => {
                        const operands = chunk.read_operands(.LessThanOrEqual, &instruction_cursor);
                        set_register(registers, operands.destination, try registers[operands.source_0.index].less_than_or_equal(registers[operands.source_1.index]));
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

        pub fn set_register(registers: []ir.Value, register: ir.Register(u8).Accessor(.Write), value: ir.Value) void {
            if (Trace.stack) {
                std.debug.print("VM -- Register update: {} <- {}\n", .{ register, value });
            }
            registers[register.index] = value;
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
    std.debug.print("IR \"chunk\" disasembly:\n", .{});
    std.debug.print("======\n", .{});
    for (instruction_list.items, 0..) |instruction, index| {
        const operation: std.meta.Tag(ir.Instruction) = @enumFromInt(@intFromEnum(instruction));
        switch (operation) {
            inline else => |op| {
                const operands = @field(instruction, @tagName(op));
                const with_info = ir.Instruction.init_with_debug_info(op, operands, registers, constants);
                std.debug.print("{d:0>4}|  {}\n", .{ index, with_info });
            },
        }
    }
    std.debug.print("-----\n", .{});

    var vm = VirtualMachine(true).init(allocator);
    defer vm.deinit();

    std.debug.print("Run virtual machine...\n", .{});
    const exit_code = try vm.interpret(&chunk);
    std.debug.print("Virtual machine has exited normally with exit-code {}!\n", .{exit_code});
}
