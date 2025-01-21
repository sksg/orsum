const std = @import("std");

const operation_code = enum(u8) {
    Constant,
    Return,
};

const bytecode = struct {
    const code_type = extern union { operation: operation_code, operand: u8 };

    code: std.ArrayList(code_type),

    pub fn init(allocator: std.mem.Allocator) bytecode {
        return bytecode{
            .code = std.ArrayList(code_type).init(allocator),
        };
    }

    pub fn deinit(self: *bytecode) void {
        self.code.deinit();
    }

    pub fn append(self: *bytecode, codes: anytype) !void {
        const codes_type = @TypeOf(codes);
        const codes_type_info = @typeInfo(codes_type);

        if (codes_type == operation_code)
            return try self.code.append(.{ .operation = codes });

        if (codes_type_info != .Struct) {
            @compileError("expected tuple or struct argument, found " ++ @typeName(codes_type));
        }

        inline for (codes_type_info.Struct.fields) |field| {
            const field_type = field.type;
            const field_name = field.name;
            switch (field_type) {
                operation_code => try self.code.append(.{ .operation = @field(codes, field_name) }),
                comptime_int, u8 => try self.code.append(.{ .operand = @field(codes, field_name) }),
                else => @compileError("expected an operation code or a u8 operand, found " ++ @typeName(field_type)),
            }
        }
    }

    const disasembler = struct {
        code: *const bytecode,
        instruction_cursor: usize,

        pub fn init(code: *const bytecode) disasembler {
            return disasembler{
                .code = code,
                .instruction_cursor = 0,
            };
        }

        pub fn operation(self: *disasembler) operation_code {
            const _operation = self.code.code.items[self.instruction_cursor].operation;
            self.instruction_cursor += 1;
            return _operation;
        }

        pub fn operand(self: *disasembler) u8 {
            const _operand = self.code.code.items[self.instruction_cursor].operand;
            self.instruction_cursor += 1;
            return _operand;
        }

        pub fn at_end(self: *disasembler) bool {
            return self.instruction_cursor >= self.code.code.items.len;
        }
    };

    pub fn disasemble(self: *const bytecode) void {
        var _disasembler = bytecode.disasembler.init(self);
        while (!_disasembler.at_end()) {
            const operation = _disasembler.operation(); // Operations are always stored before operands
            switch (operation) {
                .Constant => {
                    const operand = _disasembler.operand();
                    std.debug.print("{s}, {d}\n", .{ @tagName(operation), operand });
                },
                .Return => {
                    std.debug.print("{s}\n", .{@tagName(operation)});
                    break;
                },
            }
        }
    }
};

test "Test disasembly" {
    const allocator = std.testing.allocator;
    var chunk = bytecode.init(allocator);
    defer chunk.deinit();

    try chunk.append(.{ operation_code.Constant, 42 });
    try chunk.append(operation_code.Return);

    chunk.disasemble();
}
