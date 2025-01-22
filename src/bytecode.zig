const std = @import("std");

pub fn codepoint_type(T: type) type {
    return extern union { operation: T, operand: u8 };
}

pub fn bytecode_type(T: type) type {
    return std.ArrayList(codepoint_type(T));
}

pub fn chunk(_operation_type: type, _address_type: type) type {
    return struct {
        const operation_type = _operation_type;
        const address_type = _address_type;

        code: bytecode_type(operation_type),
        debug_info: run_length_encoded_arraylist(address_type),

        pub fn init(allocator: std.mem.Allocator) chunk(operation_type, address_type) {
            return chunk(operation_type, address_type){
                .code = bytecode_type(_operation_type).init(allocator),
                .debug_info = run_length_encoded_arraylist(address_type).init(allocator),
            };
        }

        pub fn deinit(self: *chunk(operation_type, address_type)) void {
            self.code.deinit();
            self.debug_info.deinit();
        }

        pub fn append_codepoint(self: *chunk(operation_type, address_type), address: address_type, codepoint: anytype) !void {
            if (@TypeOf(codepoint) == operation_type) {
                try self.code.append(.{ .operation = codepoint });
            } else {
                try self.code.append(.{ .operand = codepoint });
            }

            // std.debug.print("Append: {} => code.len == {}\n", .{ codepoint, self.code.items.len });

            try self.debug_info.append(address);
        }

        pub fn append_code(self: *chunk(operation_type, address_type), address: address_type, code: anytype) !void {
            // A single operation is just appended
            if (@TypeOf(code) == operation_type or @TypeOf(code) == u8)
                return try self.append_codepoint(address, code);

            if (@typeInfo(@TypeOf(code)) != .Struct) {
                @compileError("expected tuple or struct argument, found " ++ @typeName(@TypeOf(code)));
            }

            inline for (@typeInfo(@TypeOf(code)).Struct.fields) |field| {
                const codepoint = @field(code, field.name);
                switch (field.type) {
                    operation_type, comptime_int, u8 => try self.append_codepoint(address, codepoint),
                    else => @compileError("expected an operation code or a u8 operand, found " ++ @typeName(field.type)),
                }
            }
        }

        pub fn print_disasembly(self: *const chunk(operation_type, address_type)) void {
            var _disasembler = disasembler(operation_type, address_type).init(&self.code, &self.debug_info);
            _disasembler.print_disasembly();
        }

        pub fn print_disasembly_with_input(self: *const chunk(operation_type, address_type), input: [*:0]const u8) void {
            var _disasembler = disasembler(operation_type, address_type).init(&self.code, &self.debug_info);
            _disasembler.print_disasembly_with_input(input);
        }
    };
}

fn run_length_encoded_arraylist(T: type) type {
    return struct {
        encoded_data: std.ArrayList(entry_type), // Run-length encoding

        const item_type = T;
        const entry_type = struct { item: item_type, count: usize };

        pub fn init(allocator: std.mem.Allocator) run_length_encoded_arraylist(item_type) {
            return run_length_encoded_arraylist(item_type){
                .encoded_data = std.ArrayList(entry_type).init(allocator),
            };
        }

        pub fn deinit(self: *run_length_encoded_arraylist(item_type)) void {
            self.encoded_data.deinit();
        }

        pub fn append(self: *run_length_encoded_arraylist(item_type), item: item_type) !void {
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

        pub fn read_at(self: *const run_length_encoded_arraylist(item_type), item_index: usize) item_type {
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

pub fn disasembler(_operation_type: type, _address_type: type) type {
    return struct {
        code: *const bytecode_type(operation_type),
        debug_info: *const run_length_encoded_arraylist(address_type),
        cursor: usize,

        const operation_type = _operation_type;
        const address_type = _address_type;

        pub fn init(code: *const bytecode_type(operation_type), debug_info: *const run_length_encoded_arraylist(address_type)) disasembler(operation_type, address_type) {
            return disasembler(operation_type, address_type){
                .code = code,
                .debug_info = debug_info,
                .cursor = 0,
            };
        }

        pub fn read_operation(self: *disasembler(operation_type, address_type)) operation_type {
            const operation = self.code.items[self.cursor].operation;
            self.cursor += 1;
            return operation;
        }

        pub fn read_operand(self: *disasembler(operation_type, address_type)) u8 {
            const operand = self.code.items[self.cursor].operand;
            self.cursor += 1;
            return operand;
        }

        pub fn is_at_end(self: *disasembler(operation_type, address_type)) bool {
            return self.cursor >= self.code.items.len;
        }

        pub fn print_disasembly(self: *disasembler(operation_type, address_type)) void {
            self.cursor = 0;

            const type_name = @typeName(disasembler(operation_type, address_type));
            std.debug.print("Disassembly of " ++ type_name ++ ":\n", .{});
            const title_width = type_name.len + 17;
            const first_half_width = (title_width - 23) / 2;
            const second_half_width = title_width - first_half_width - 23;
            std.debug.print("{s:-<" ++ int_to_string(first_half_width) ++ "} Bytecode length: {d:0>4} {s:-<" ++ int_to_string(second_half_width) ++ "}\n", .{ "", self.code.items.len, "" });

            while (!self.is_at_end()) {
                const index = self.cursor;
                //const _address = self.debug.read_address();
                const operation = self.read_operation(); // Operations are always stored before operands
                if (!operation_type.disasemble(self, index, operation)) break;
            }
            std.debug.print("{s:-<" ++ int_to_string(title_width) ++ "}\n", .{""});
        }

        pub fn print_disasembly_with_input(self: *disasembler(operation_type, address_type), input: [*:0]const u8) void {
            self.cursor = 0;

            const type_name = @typeName(disasembler(operation_type, address_type));
            std.debug.print("Disassembly of " ++ type_name ++ ":\n", .{});
            const title_width = type_name.len + 17;
            const first_half_width = (title_width - 23) / 2;
            const second_half_width = title_width - first_half_width - 23;
            std.debug.print("{s:=<" ++ int_to_string(first_half_width) ++ "} Bytecode length: {d:0>4} {s:=<" ++ int_to_string(second_half_width) ++ "}\n", .{ "", self.code.items.len, "" });

            var line: [*]const u8 = input[0..];
            var line_len: usize = 0;
            var line_number: usize = 0;
            while (true) {
                if (line[line_len] == '\n' or line[line_len] == 0) {
                    // New line of input detected
                    var previous_address: ?address_type = null;
                    while (!self.is_at_end()) {
                        const token_address = self.debug_info.read_at(self.cursor);
                        const column_number = @intFromPtr(token_address) - @intFromPtr(line);

                        if (column_number > line_len) break;
                        if (token_address != previous_address) {
                            // New token to process:
                            if (previous_address != null)
                                std.debug.print("\n", .{});
                            std.debug.print("Token @ ln {d}, col {d}\n", .{ line_number, column_number });
                            std.debug.print("> {s}\n  ", .{line[0..line_len]});
                            for (0..column_number) |_| std.debug.print(" ", .{});
                            std.debug.print("^\n", .{});
                            previous_address = token_address;
                        }
                        const index = self.cursor;
                        const operation = self.read_operation(); // Operations are always stored before operands
                        if (!operation_type.disasemble(self, index, operation)) break;
                    }
                    line_number += 1;
                    line = line + line_len;
                    line_len = 0;
                }
                if (line[line_len] == 0) break;
                line_len += 1;
            }

            std.debug.print("{s:-<" ++ int_to_string(title_width) ++ "}\n", .{""});
        }

        const disasemble_operation_len = blk: {
            var max_len: usize = 0;
            for (@typeInfo(operation_type).Enum.fields) |field| {
                if (field.name.len > max_len) {
                    max_len = field.name.len;
                }
            }
            break :blk max_len;
        };

        pub fn disasemble_operation(operation: operation_type, comptime padding: u8, comptime alignment: u8) [disasemble_operation_len]u8 {
            var buffer: [disasemble_operation_len]u8 = undefined;
            _ = std.fmt.bufPrint(buffer[0..], "{s:" ++ .{ padding, alignment } ++ int_to_string(disasemble_operation_len) ++ "}", .{@tagName(operation)}) catch unreachable;
            return buffer;
        }
    };
}

fn int_to_string_len(comptime value: anytype) usize {
    var buffer: [20]u8 = undefined; // Enough to hold any 32-bit integer
    const slice = std.fmt.bufPrint(buffer[0..], "{}", .{value}) catch unreachable;
    return slice.len;
}

fn int_to_string(comptime value: anytype) [int_to_string_len(value)]u8 {
    var buffer: [20]u8 = undefined; // Enough to hold any 32-bit integer
    const slice = std.fmt.bufPrint(buffer[0..], "{}", .{value}) catch unreachable;
    return slice[0..int_to_string_len(value)].*;
}

pub fn print_operation_set_disassembly(operation_type: type) void {
    const _disasembler = disasembler(operation_type, struct {});
    const type_name = @typeName(operation_type);
    std.debug.print("Disassembly of " ++ type_name ++ ":\n", .{});
    const title_width = type_name.len + 16;
    const item_width = _disasembler.disasemble_operation_len * 2 + type_name.len + 7;
    const table_width = if (title_width > item_width) title_width else item_width;
    std.debug.print("{s:-<" ++ int_to_string(table_width) ++ "}\n", .{""});
    inline for (@typeInfo(operation_type).Enum.fields) |field| {
        const operation = @field(operation_type, field.name);
        std.debug.print("{s} |=> {}\n", .{ _disasembler.disasemble_operation(operation, ' ', '>'), operation });
    }
    std.debug.print("{s:-<" ++ int_to_string(table_width) ++ "}\n", .{""});
}
