const std = @import("std");
const bytecode = @import("bytecode.zig");

const operation_code = enum(u8) {
    Load,
    Exit,

    pub fn disasemble(disasembler: anytype, index: usize, operation: operation_code) bool {
        const disasembled = @TypeOf(disasembler.*).disasemble_operation(operation, ' ', '>');
        switch (operation) {
            .Load => {
                const operand = disasembler.read_operand();
                std.debug.print("{d:0>4}| {s} {d}\n", .{ index, disasembled, operand });
            },
            .Exit => {
                const operand = disasembler.read_operand();
                std.debug.print("{d:0>4}| {s} {d}\n", .{ index, disasembled, operand });
                return false;
            },
        }
        return true;
    }
};

const address_type = [*]const u8;

test "test .disasemble() of single operation codes" {
    bytecode.print_operation_set_disassembly(operation_code);
}

const bytecode_chunk = bytecode.chunk(operation_code, address_type);

test "Test disasembly" {
    const allocator = std.testing.allocator;

    const dummy_input = "dummy input";

    var code_chunk = bytecode_chunk.init(allocator);
    defer code_chunk.deinit();

    try code_chunk.append_code(dummy_input.ptr[0..], .{ operation_code.Load, 42 });
    try code_chunk.append_code(dummy_input.ptr[6..], .{ operation_code.Exit, 0 });

    code_chunk.print_disasembly();
    code_chunk.print_disasembly_with_input(dummy_input);
}

// const VirtualMachine = struct {
//     code_chunk: bytecode.code_chunk,

//     fn interpret(self: VirtualMachine) void {
//         for (self.code_chunk.operations()) |op| {
//             switch (op) {
//                 .Return => {
//                     return;
//                 },
//             }
//         }
//     }
// };
