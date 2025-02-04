const std = @import("std");

pub fn Chunk(_InstructionSet: type, _AddressType: type) type {
    return struct {
        const Self = @This();
        pub const InstructionSet = _InstructionSet;
        pub const OperationType = std.meta.Tag(_InstructionSet);
        pub fn OperandType(comptime operation: OperationType) type {
            return @TypeOf(@field(@unionInit(InstructionSet, @tagName(operation), undefined), @tagName(operation)));
        }
        pub const AddressType = _AddressType;

        pub const ConstantTypeTag = enum { u8, u16, u32, u64, i8, i16, i32, i64, f32, f64 };
        pub const ContantType = union(ConstantTypeTag) { u8: u8, u16: u16, u32: u32, u64: u64, i8: i8, i16: i16, i32: i32, i64: i64, f32: f32, f64: f64 };

        bytecode: std.ArrayList(u8),
        constants: std.ArrayList(ContantType),
        debug_info: RunLengthEncodedArrayList(AddressType),

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .bytecode = std.ArrayList(u8).init(allocator),
                .constants = std.ArrayList(ContantType).init(allocator),
                .debug_info = RunLengthEncodedArrayList(AddressType).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.bytecode.deinit();
            self.constants.deinit();
            self.debug_info.deinit();
        }

        pub fn append_instruction(self: *Self, address: ?AddressType, comptime operation: OperationType, operands: Self.OperandType(operation)) !void {
            // A single operation is just appended
            try self.bytecode.append(@intFromEnum(operation));
            if (address) |addr| try self.debug_info.append(addr);

            inline for (@typeInfo(@TypeOf(operands)).Struct.fields) |field| {
                const operand = @field(operands, field.name);
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
            }
        }

        pub fn append_constant(self: *Self, constant: ContantType) !u32 {
            try self.constants.append(constant);
            return @intCast(self.constants.items.len - 1);
        }

        pub fn read_operation(self: Self, cursor: *usize) OperationType {
            const operation: OperationType = @enumFromInt(self.bytecode.items[cursor.*]);
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

        pub fn read_operands(self: Self, comptime operation: OperationType, cursor: *usize) OperandType(operation) {
            var operands: OperandType(operation) = undefined;
            inline for (@typeInfo(OperandType(operation)).Struct.fields) |field| {
                @field(operands, field.name) = self.read_operand(field.type, cursor);
            }
            return operands;
        }

        pub fn read_instruction(self: Self, cursor: *usize) InstructionSet {
            const operation = self.read_operation(cursor);
            switch (operation) {
                inline else => |op| {
                    var operands: OperandType(op) = undefined;
                    inline for (@typeInfo(OperandType(op)).Struct.fields) |field| {
                        @field(operands, field.name) = self.read_operand(field.type, cursor);
                    }
                    return @unionInit(InstructionSet, @tagName(op), operands);
                },
            }
        }

        pub fn unpack_into_instruction_list(self: Self, instruction_list: *std.ArrayList(InstructionSet)) !void {
            var cursor: usize = 0;
            while (cursor < self.bytecode.items.len) {
                try instruction_list.append(self.read_instruction(&cursor));
            }
        }
    };
}

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

            // Else we need to append a new address
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
