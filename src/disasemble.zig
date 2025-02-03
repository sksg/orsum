const std = @import("std");

pub fn InstructionSetInfo(_InstructionSet: type) type {
    return struct {
        const Self = @This();
        const InstructionSet: type = _InstructionSet;
        const OperationType: type = std.meta.Tag(InstructionSet);
        pub fn OperandType(comptime operation: OperationType) type {
            return @TypeOf(@field(@unionInit(InstructionSet, @tagName(operation), undefined), @tagName(operation)));
        }
        pub fn dummy_operands(comptime operation: OperationType) Self.OperandType(operation) {
            var dummy_value: Self.OperandType(operation) = undefined;
            inline for (@typeInfo(Self.OperandType(operation)).Struct.fields) |field| {
                @field(dummy_value, field.name) = @intCast((std.math.pow(u128, 2, @bitSizeOf(field.type))) - 1);
            }
            return dummy_value;
        }

        pub fn dummy_instruction_list(comptime N: usize) [N]InstructionSet {
            const M = @typeInfo(Self.InstructionSet).Union.fields.len;
            var dummy_list: [N]InstructionSet = undefined;
            inline for (0..N) |index| {
                const field = @typeInfo(Self.InstructionSet).Union.fields[index % M];
                const operation = @field(InstructionSet, field.name);
                dummy_list[index] = @unionInit(InstructionSet, field.name, dummy_operands(operation));
            }
            return dummy_list;
        }
    };
}

pub fn instruction_type(comptime InstructionSet: type, comptime operation: InstructionSetInfo(InstructionSet).OperationType) [InstructionDisasembler(InstructionSet, .{}).disasemble_len(operation, false)]u8 {
    return comptime InstructionDisasembler(InstructionSet, .{}).disasemble(operation, null, null);
}

pub fn instruction_value(comptime InstructionSet: type, position: usize, comptime operation: InstructionSetInfo(InstructionSet).OperationType, operands: InstructionSetInfo(InstructionSet).OperandType(operation)) [InstructionDisasembler(InstructionSet, .{}).disasemble_len(operation, true)]u8 {
    const _disasembler = comptime InstructionDisasembler(InstructionSet, .{});
    return _disasembler.disasemble(operation, operands, position);
}

pub fn instruction_set(comptime InstructionSet: type) [InstructionListDisasembler(InstructionSet, .{}, .{}).disasemble_len(0, false)]u8 {
    return comptime InstructionListDisasembler(InstructionSet, .{}, .{}).disasemble(0, null);
}

pub fn types_ruler(comptime InstructionSet: type, comptime pattern: []const u8) [InstructionListDisasembler(InstructionSet, .{}, .{}).ruler_type_width()]u8 {
    return comptime InstructionListDisasembler(InstructionSet, .{}, .{}).ruler_type(pattern);
}

pub fn values_ruler(comptime InstructionSet: type, comptime pattern: []const u8) [InstructionListDisasembler(InstructionSet, .{}, .{}).ruler_value_width()]u8 {
    return comptime InstructionListDisasembler(InstructionSet, .{}, .{}).ruler_value(pattern);
}

pub fn instruction_list(comptime InstructionSet: type, comptime N: usize, instructions: []InstructionSet) [InstructionListDisasembler(InstructionSet, .{}, .{}).disasemble_len(N, true)]u8 {
    const _disasembler = comptime InstructionListDisasembler(InstructionSet, .{}, .{});
    return _disasembler.disasemble(N, instructions);
}

pub fn runtime_fmt(comptime N: usize, comptime fmt_padding: [2]u8, comptime fmt: []const u8, args: anytype) [N]u8 {
    var buffer: [N]u8 = undefined;
    const slice = std.fmt.bufPrint(&buffer, fmt, args) catch unreachable;
    const padding = comptime ":" ++ fmt_padding ++ int_to_string(N);
    var buffer2: [N]u8 = undefined;
    _ = std.fmt.bufPrint(&buffer2, "{s" ++ padding ++ "}", .{slice}) catch unreachable;
    return buffer2;
}

pub fn comptime_fmt(comptime fmt: []const u8, comptime args: anytype) [std.fmt.count(fmt, args)]u8 {
    var buffer: [std.fmt.count(fmt, args)]u8 = undefined;
    _ = std.fmt.bufPrint(&buffer, fmt, args) catch unreachable;
    return buffer;
}

pub const InstructionDisasemblerFormattingOptions = struct {
    type: []const u8 = "[{[sizeof]s}] {[operation_code]s} | {[operand_fields]s} ;; {[note]s}",
    value: []const u8 = "|{[position]s}| {[operation_code]s} | {[operand_values]s} ;; {[operand_fields]s} // {[note]s}",

    sizeof: []const u8 = "+{[size]d}b",
    sizeof_padding: ?[2]u8 = .{ ' ', '>' },

    position: []const u8 = "{[position]d}",
    position_width: usize = 4,
    position_padding: [2]u8 = .{ '0', '>' },

    note: []const u8 = "{[note]s}",
    note_padding: ?[2]u8 = null,

    operation_code: []const u8 = ".{[operation_code]s}",
    operation_code_padding: ?[2]u8 = .{ ' ', '>' },

    operand_fields: []const u8 = "{[operand_fields]s}",
    operand_fields_padding: ?[2]u8 = .{ ' ', '<' },
    operand_fields_separator: []const u8 = ", ",

    operand_field: []const u8 = "{[operand_name]s}({[operand_type]s})",
    operand_value: []const u8 = "{[operand_value]d}",
    operand_field_padding: ?[2]u8 = null,
};

pub fn InstructionDisasembler(_InstructionSet: type, _Fmt: InstructionDisasemblerFormattingOptions) type {
    return struct {
        const Self = @This();
        const InstructionSet = _InstructionSet;
        const Info = InstructionSetInfo(InstructionSet);
        const OperationType = Info.OperationType;
        pub fn OperandType(comptime operation: OperationType) type {
            return Info.OperandType(operation);
        }
        const Fmt = _Fmt;

        pub fn comptime_operands_return(comptime operation: OperationType, comptime has_value: bool) type {
            if (has_value)
                return OperandType(operation)
            else
                return @TypeOf(null);
        }

        pub fn comptime_operands(comptime operation: OperationType, comptime has_value: bool) comptime_operands_return(operation, has_value) {
            if (has_value)
                return Info.dummy_operands(operation)
            else
                return null;
        }

        pub inline fn is_value(maybe_value: anytype) bool {
            return @TypeOf(maybe_value) != @TypeOf(null);
        }

        pub inline fn is_value_type(comptime maybe_value_type: type) bool {
            return maybe_value_type != @TypeOf(null);
        }

        pub fn disasemble_len(comptime operation: OperationType, comptime has_value: bool) usize {
            if (has_value)
                return std.fmt.count(Fmt.value, .{
                    .position = fmt_padded_position(std.math.pow(usize, 10, Fmt.position_width - 1)),
                    .note = fmt_padded_note(operation),
                    .operation_code = fmt_padded_operation_code(operation),
                    .operand_values = fmt_padded_operand_fields(operation, Info.dummy_operands(operation)),
                    .operand_fields = fmt_padded_operand_fields(operation, null),
                })
            else
                return std.fmt.count(Fmt.type, .{
                    .sizeof = fmt_padded_sizeof(operation),
                    .note = fmt_padded_note(operation),
                    .operation_code = fmt_padded_operation_code(operation),
                    .operand_fields = fmt_padded_operand_fields(operation, null),
                });
        }

        pub fn disasemble(comptime operation: OperationType, operands: anytype, position: ?usize) [
            disasemble_len(operation, is_value_type(@TypeOf(operands)))
        ]u8 {
            if (position) |pos| {
                _ = pos + 1;
            }
            if (is_value(operands))
                return runtime_fmt(
                    disasemble_len(operation, is_value_type(@TypeOf(operands))),
                    " >".*,
                    Fmt.value,
                    .{
                        .position = fmt_padded_position(position.?),
                        .note = fmt_padded_note(operation),
                        .operation_code = fmt_padded_operation_code(operation),
                        .operand_values = fmt_padded_operand_fields(operation, operands),
                        .operand_fields = fmt_padded_operand_fields(operation, null),
                    },
                )
            else
                return comptime_fmt(Fmt.type, .{
                    .sizeof = fmt_padded_sizeof(operation),
                    .note = fmt_padded_note(operation),
                    .operation_code = fmt_padded_operation_code(operation),
                    .operand_fields = fmt_padded_operand_fields(operation, null),
                });
        }

        pub fn fmt_padded_sizeof_len(comptime operation: OperationType) usize {
            const padding = comptime if (Fmt.sizeof_padding) |pad| ":" ++ pad ++ int_to_string(sizeof_width()) else "";
            return std.fmt.count("{s" ++ padding ++ "}", .{fmt_sizeof(operation)});
        }

        pub fn fmt_padded_sizeof(comptime operation: OperationType) [fmt_padded_sizeof_len(operation)]u8 {
            const padding = comptime if (Fmt.sizeof_padding) |pad| ":" ++ pad ++ int_to_string(sizeof_width()) else "";
            return comptime_fmt("{s" ++ padding ++ "}", .{fmt_sizeof(operation)});
        }

        pub fn sizeof_width() usize {
            var max_width: usize = 0;
            inline for (@typeInfo(InstructionSet).Union.fields) |field| {
                const len = fmt_sizeof_len(@field(InstructionSet, field.name));
                if (len > max_width)
                    max_width = len;
            }
            return max_width;
        }

        pub fn fmt_sizeof_len(comptime operation: OperationType) usize {
            return std.fmt.count(Fmt.sizeof, .{ .size = sizeof(operation) / 8 });
        }

        pub fn fmt_sizeof(comptime operation: OperationType) [fmt_sizeof_len(operation)]u8 {
            return comptime_fmt(Fmt.sizeof, .{ .size = sizeof(operation) / 8 });
        }

        pub fn sizeof(comptime operation: OperationType) usize {
            var size: usize = @bitSizeOf(OperationType);
            for (@typeInfo(OperandType(operation)).Struct.fields) |_operand| {
                size += @bitSizeOf(_operand.type);
            }
            return size;
        }

        pub fn fmt_padded_position_len() usize {
            const padding = comptime ":" ++ Fmt.position_padding ++ int_to_string(Fmt.position_width);
            return std.fmt.count("{s" ++ padding ++ "}", .{fmt_position(std.math.pow(usize, 10, Fmt.position_width - 1))});
        }

        pub fn fmt_padded_position(position: usize) [fmt_padded_position_len()]u8 {
            return runtime_fmt(fmt_padded_position_len(), Fmt.position_padding, "{s}", .{fmt_position(position)});
        }

        pub fn fmt_position_len() usize {
            return std.fmt.count(Fmt.position, .{ .position = std.math.pow(usize, 10, Fmt.position_width - 1) });
        }

        pub fn fmt_position(position: usize) [fmt_position_len()]u8 {
            return runtime_fmt(fmt_position_len(), Fmt.position_padding, Fmt.position, .{ .position = position });
        }

        pub fn fmt_padded_note_len(comptime operation: OperationType) usize {
            const padding = if (Fmt.note_padding) |_padding| ":" ++ _padding ++ int_to_string(note_padding_width()) else "";
            return std.fmt.count("{s" ++ padding ++ "}", .{fmt_note(operation)});
        }

        pub fn fmt_padded_note(comptime operation: OperationType) [fmt_padded_note_len(operation)]u8 {
            const padding = if (Fmt.note_padding) |_padding| ":" ++ _padding ++ int_to_string(note_padding_width()) else "";
            return comptime_fmt("{s" ++ padding ++ "}", .{fmt_note(operation)});
        }

        pub fn note_padding_width() usize {
            var max_width: usize = 0;
            inline for (@typeInfo(InstructionSet).Union.fields) |field| {
                const len = fmt_note_len(@field(InstructionSet, field.name));
                if (len > max_width)
                    max_width = len;
            }
            return max_width;
        }

        pub fn fmt_note_len(comptime operation: OperationType) usize {
            return std.fmt.count(Fmt.note, .{ .note = OperandType(operation).__note });
        }

        pub fn fmt_note(comptime operation: OperationType) [fmt_note_len(operation)]u8 {
            return comptime_fmt(Fmt.note, .{ .note = OperandType(operation).__note });
        }

        pub fn fmt_padded_operation_code_len(comptime operation: OperationType) usize {
            const padding = comptime if (Fmt.operation_code_padding) |pad| ":" ++ pad ++ int_to_string(operation_code_width()) else "";
            return std.fmt.count("{s" ++ padding ++ "}", .{fmt_operation_code(operation)});
        }

        pub fn fmt_padded_operation_code(comptime operation: OperationType) [fmt_padded_operation_code_len(operation)]u8 {
            const padding = comptime if (Fmt.operation_code_padding) |pad| ":" ++ pad ++ int_to_string(operation_code_width()) else "";
            return comptime_fmt("{s" ++ padding ++ "}", .{fmt_operation_code(operation)});
        }

        pub fn operation_code_width() usize {
            var max_width: usize = 0;
            inline for (@typeInfo(InstructionSet).Union.fields) |field| {
                const len = fmt_operation_code_len(@field(InstructionSet, field.name));
                if (len > max_width)
                    max_width = len;
            }
            return max_width;
        }

        pub fn fmt_operation_code_len(comptime operation: OperationType) usize {
            return std.fmt.count(Fmt.operation_code, .{ .operation_code = @tagName(operation) });
        }

        pub fn fmt_operation_code(comptime operation: OperationType) [fmt_operation_code_len(operation)]u8 {
            return comptime_fmt(Fmt.operation_code, .{ .operation_code = @tagName(operation) });
        }

        pub fn fmt_padded_operand_fields_len(comptime operation: OperationType, comptime has_value: bool) usize {
            const padding = comptime if (Fmt.operand_fields_padding) |pad| ":" ++ pad ++ int_to_string(operand_fields_width(has_value)) else "";
            return std.fmt.count("{s" ++ padding ++ "}", .{fmt_operand_fields(operation, comptime_operands(operation, has_value))});
        }

        pub fn fmt_padded_operand_fields(comptime operation: OperationType, operands: anytype) [fmt_padded_operand_fields_len(operation, is_value_type(@TypeOf(operands)))]u8 {
            const padding = comptime if (Fmt.operand_fields_padding) |pad| ":" ++ pad ++ int_to_string(operand_fields_width(is_value_type(@TypeOf(operands)))) else "";
            return runtime_fmt(
                fmt_padded_operand_fields_len(operation, is_value_type(@TypeOf(operands))),
                " >"[0..].*,
                "{s" ++ padding ++ "}",
                .{fmt_operand_fields(operation, operands)},
            );
        }

        pub fn operand_fields_width(comptime has_value: bool) usize {
            var max_width: usize = 0;
            inline for (@typeInfo(InstructionSet).Union.fields) |field| {
                const operation = @field(InstructionSet, field.name);
                const len = fmt_operand_fields_len(operation, has_value);
                if (len > max_width)
                    max_width = len;
            }
            return max_width;
        }

        pub fn fmt_operand_fields_len(comptime operation: OperationType, comptime has_value: bool) usize {
            return std.fmt.count(Fmt.operand_fields, .{ .operand_fields = fmt_operand_fields_impl(operation, comptime_operands(operation, has_value)) });
        }

        pub fn fmt_operand_fields(comptime operation: OperationType, operands: anytype) [fmt_operand_fields_len(operation, is_value_type(@TypeOf(operands)))]u8 {
            return runtime_fmt(
                fmt_operand_fields_len(operation, is_value_type(@TypeOf(operands))),
                " >"[0..].*,
                Fmt.operand_fields,
                .{ .operand_fields = fmt_operand_fields_impl(operation, operands) },
            );
        }

        pub fn fmt_operand_fields_impl_len(comptime operation: OperationType, comptime has_value: bool) usize {
            var len: usize = 0;
            inline for (@typeInfo(OperandType(operation)).Struct.fields, 0..) |_, index| {
                len += fmt_padded_operand_field_len(operation, index, has_value);
                if (index < @typeInfo(OperandType(operation)).Struct.fields.len - 1) {
                    len += Fmt.operand_fields_separator.len;
                }
            }
            return len;
        }

        pub fn fmt_operand_fields_impl(comptime operation: OperationType, operands: anytype) [fmt_operand_fields_impl_len(operation, is_value_type(@TypeOf(operands)))]u8 {
            var buffer: [fmt_operand_fields_impl_len(operation, is_value_type(@TypeOf(operands)))]u8 = undefined;
            var cursor: usize = 0;
            inline for (@typeInfo(OperandType(operation)).Struct.fields, 0..) |_, index| {
                var buffer2: [fmt_padded_operand_field_len(operation, index, is_value_type(@TypeOf(operands)))]u8 = undefined;
                const slice = std.fmt.bufPrint(buffer[cursor..], "{s}", .{fmt_padded_operand_field(operation, index, operands, &buffer2)}) catch unreachable;
                cursor += slice.len;
                if (index < @typeInfo(OperandType(operation)).Struct.fields.len - 1) {
                    _ = std.fmt.bufPrint(buffer[cursor..], "{s}", .{Fmt.operand_fields_separator}) catch unreachable;
                    cursor += Fmt.operand_fields_separator.len;
                }
            }
            var buffer3: [fmt_operand_fields_impl_len(operation, is_value_type(@TypeOf(operands)))]u8 = undefined;
            _ = std.fmt.bufPrint(&buffer3, "{s: <" ++ int_to_string(fmt_operand_fields_impl_len(operation, is_value_type(@TypeOf(operands)))) ++ "}", .{buffer[0..cursor]}) catch unreachable;
            return buffer3;
        }

        pub fn fmt_padded_operand_field_len(comptime operation: OperationType, comptime operand_index: usize, comptime has_value: bool) usize {
            const padding = comptime if (Fmt.operand_field_padding) |pad| ":" ++ pad ++ int_to_string(operand_field_width(operand_index, has_value)) else "";
            var buffer: [fmt_operand_field_len(operation, operand_index, has_value)]u8 = undefined;
            return std.fmt.count("{s" ++ padding ++ "}", .{fmt_operand_field(operation, operand_index, comptime_operands(operation, has_value), &buffer)});
        }

        pub fn fmt_padded_operand_field(comptime operation: OperationType, comptime operand_index: usize, operands: anytype, buffer: *[fmt_padded_operand_field_len(operation, operand_index, is_value_type(@TypeOf(operands)))]u8) []u8 {
            const padding = comptime if (Fmt.operand_field_padding) |pad| ":" ++ pad ++ int_to_string(operand_field_width(operand_index, is_value_type(@TypeOf(operands)))) else "";
            var buffer2: [fmt_operand_field_len(operation, operand_index, is_value_type(@TypeOf(operands)))]u8 = undefined;
            return std.fmt.bufPrint(buffer, "{s" ++ padding ++ "}", .{fmt_operand_field(operation, operand_index, operands, &buffer2)}) catch unreachable;
        }

        pub fn operand_field_width(comptime operand_index: usize, comptime has_value: bool) usize {
            var max_width: usize = 0;
            inline for (@typeInfo(InstructionSet).Union.fields) |field| {
                const operation = @field(InstructionSet, field.name);
                const len = fmt_operand_field_len(operation, operand_index, has_value);
                if (len > max_width)
                    max_width = len;
            }
            return max_width;
        }

        pub fn fmt_operand_field_len(comptime operation: OperationType, comptime operand_index: usize, comptime has_value: bool) usize {
            const field = @typeInfo(OperandType(operation)).Struct.fields[operand_index];
            if (has_value) {
                const value = @field(Info.dummy_operands(operation), field.name);
                return std.fmt.count(Fmt.operand_value, .{ .operand_value = value });
            } else {
                return std.fmt.count(Fmt.operand_field, .{ .operand_name = field.name, .operand_type = @typeName(field.type) });
            }
        }

        pub fn fmt_operand_field(comptime operation: OperationType, comptime operand_index: usize, operands: anytype, buffer: *[fmt_operand_field_len(operation, operand_index, is_value_type(@TypeOf(operands)))]u8) []u8 {
            const field = @typeInfo(OperandType(operation)).Struct.fields[operand_index];
            if (is_value(operands)) {
                const value = @field(operands, field.name);
                return std.fmt.bufPrint(buffer, Fmt.operand_value, .{ .operand_value = value }) catch unreachable;
            } else {
                return std.fmt.bufPrint(buffer, Fmt.operand_field, .{ .operand_name = field.name, .operand_type = @typeName(field.type) }) catch unreachable;
            }
        }
    };
}

const InstructionListDisasemblerFormattingOptions = struct {
    instruction_set: []const u8 = "{[instruction_set]s}",

    instruction_padding: ?[2]u8 = null,
    instruction_separator: []const u8 = "\n",
};

pub fn InstructionListDisasembler(_InstructionSet: type, _InstructionFmt: InstructionDisasemblerFormattingOptions, _InstructionListFmt: InstructionListDisasemblerFormattingOptions) type {
    return struct {
        const Self = @This();
        const InstructionSet = _InstructionSet;
        const Info = InstructionSetInfo(InstructionSet);
        const OperationType = Info.OperationType;
        pub fn OperandType(comptime operation: OperationType) type {
            return Info.OperandType(operation);
        }

        const Fmt = _InstructionListFmt;
        const instruction_disasembler = InstructionDisasembler(InstructionSet, _InstructionFmt);

        pub fn comptime_instructions_return(comptime N: usize, comptime has_value: bool) type {
            if (has_value)
                return [N]InstructionSet
            else
                return @TypeOf(null);
        }

        pub fn comptime_instructions(comptime N: usize, comptime has_value: bool) comptime_instructions_return(N, has_value) {
            if (has_value)
                return Info.dummy_instruction_list(N)
            else
                return null;
        }

        pub inline fn is_value(maybe_value: anytype) bool {
            return @TypeOf(maybe_value) != @TypeOf(null);
        }

        pub inline fn is_value_type(comptime maybe_value_type: type) bool {
            return maybe_value_type != @TypeOf(null);
        }

        pub fn disasemble(comptime N: usize, instructions: anytype) [disasemble_len(N, is_value_type(@TypeOf(instructions)))]u8 {
            return runtime_fmt(
                disasemble_len(N, is_value_type(@TypeOf(instructions))),
                " >".*,
                Fmt.instruction_set,
                .{ .instruction_set = fmt_instruction_set_impl(N, instructions) },
            );
        }

        pub fn disasemble_len(comptime N: usize, comptime has_value: bool) usize {
            return std.fmt.count(Fmt.instruction_set, .{ .instruction_set = fmt_instruction_set_impl(N, comptime_instructions(N, has_value)) });
        }

        pub fn ruler_type(comptime pattern: []const u8) [ruler_type_width()]u8 {
            const full_pattern = pattern ** ((ruler_type_width() / pattern.len) + 1);
            return full_pattern[0..ruler_type_width()].*;
        }

        pub fn ruler_type_width() usize {
            const _disasembly = disasemble(0, null);
            var maximum_width: usize = 0;
            var width_counter: usize = 0;
            for (_disasembly) |character| {
                if (character != '\n')
                    width_counter += 1
                else if (width_counter > maximum_width) {
                    maximum_width = width_counter;
                    width_counter = 0;
                } else width_counter = 0;
            }
            return maximum_width;
        }

        pub fn ruler_value(comptime pattern: []const u8) [ruler_value_width()]u8 {
            const full_pattern = pattern ** ((ruler_value_width() / pattern.len) + 1);
            return full_pattern[0..ruler_value_width()].*;
        }

        pub fn ruler_value_width() usize {
            const N = @typeInfo(InstructionSet).Union.fields.len;
            const _disasembly = disasemble(N, comptime_instructions(N, true));
            var maximum_width: usize = 0;
            var width_counter: usize = 0;
            for (_disasembly) |character| {
                if (character != '\n')
                    width_counter += 1
                else if (width_counter > maximum_width) {
                    maximum_width = width_counter;
                    width_counter = 0;
                } else width_counter = 0;
            }
            return maximum_width;
        }

        pub fn fmt_instruction_set_impl_len(comptime N: usize, comptime has_value: bool) usize {
            const instruction_count = if (has_value) N else @typeInfo(InstructionSet).Union.fields.len;
            var len: usize = 0;
            for (0..instruction_count) |index| {
                len += fmt_padded_instruction_len(N, has_value, index);
                if (index < instruction_count - 1) {
                    len += Fmt.instruction_separator.len;
                }
            }
            return len;
        }

        pub fn fmt_instruction_set_impl(comptime N: usize, instructions: anytype) [fmt_instruction_set_impl_len(N, is_value_type(@TypeOf(instructions)))]u8 {
            const instruction_count = if (is_value_type(@TypeOf(instructions))) N else @typeInfo(InstructionSet).Union.fields.len;
            var buffer: [fmt_instruction_set_impl_len(N, is_value_type(@TypeOf(instructions)))]u8 = undefined;
            var cursor: usize = 0;
            inline for (0..instruction_count) |index| {
                _ = std.fmt.bufPrint(buffer[cursor..], "{s}", .{fmt_padded_instruction(N, instructions, index)}) catch unreachable;
                cursor += fmt_padded_instruction_len(N, is_value_type(@TypeOf(instructions)), index);
                if (index < instruction_count - 1) {
                    _ = std.fmt.bufPrint(buffer[cursor..], "{s}", .{Fmt.instruction_separator}) catch unreachable;
                    cursor += Fmt.instruction_separator.len;
                }
            }
            return buffer;
        }

        pub fn fmt_padded_instruction_len(comptime N: usize, comptime has_value: bool, comptime index: usize) usize {
            if (has_value) {
                const padding = comptime ": >" ++ int_to_string(instruction_padding_len(true));
                const instruction = comptime_instructions(N, true)[index];
                const operation: OperationType = @enumFromInt(@intFromEnum(instruction));
                switch (operation) {
                    inline else => |op| {
                        const operands = @field(instruction, @tagName(op));
                        return std.fmt.count("{s" ++ padding ++ "}", .{instruction_disasembler.disasemble(op, operands, index)});
                    },
                }
            } else {
                const padding = if (Fmt.instruction_padding) |_padding| ":" ++ _padding ++ int_to_string(instruction_padding_len(false)) else "";
                const instruction_operation_code = @field(InstructionSet, @typeInfo(InstructionSet).Union.fields[index].name);
                return std.fmt.count("{s" ++ padding ++ "}", .{instruction_disasembler.disasemble(instruction_operation_code, null, null)});
            }
        }

        pub fn fmt_padded_instruction(comptime N: usize, instructions: anytype, comptime index: usize) [fmt_padded_instruction_len(N, is_value_type(@TypeOf(instructions)), index)]u8 {
            if (is_value_type(@TypeOf(instructions))) {
                const padding = comptime ": >" ++ int_to_string(instruction_padding_len(true));
                const instruction = instructions[index];
                const operation: OperationType = @enumFromInt(@intFromEnum(instruction));
                var buffer: [fmt_padded_instruction_len(N, is_value_type(@TypeOf(instructions)), index)]u8 = undefined;
                switch (operation) {
                    inline else => |op| {
                        const operands = @field(instruction, @tagName(op));
                        _ = std.fmt.bufPrint(&buffer, "{s" ++ padding ++ "}", .{instruction_disasembler.disasemble(op, operands, index)}) catch unreachable;
                    },
                }
                return buffer;
            } else {
                const padding = if (Fmt.instruction_padding) |_padding| ":" ++ _padding ++ int_to_string(instruction_padding_len(false)) else "";
                const instruction_operation_code = @field(InstructionSet, @typeInfo(InstructionSet).Union.fields[index].name);
                var buffer: [fmt_padded_instruction_len(N, is_value_type(@TypeOf(instructions)), index)]u8 = undefined;
                _ = std.fmt.bufPrint(&buffer, "{s" ++ padding ++ "}", .{instruction_disasembler.disasemble(instruction_operation_code, null, null)}) catch unreachable;
                return buffer;
            }
        }

        pub fn instruction_padding_len(comptime has_value: bool) usize {
            var max_width: usize = 0;
            for (@typeInfo(InstructionSet).Union.fields) |field| {
                const operation = @field(InstructionSet, field.name);
                const len = instruction_disasembler.disasemble_len(operation, has_value);
                if (len > max_width)
                    max_width = len;
            }
            return max_width;
        }
    };
}

fn int_to_string_len(comptime value: anytype) usize {
    return std.fmt.count("{}", .{value});
}

fn int_to_string(comptime value: anytype) [int_to_string_len(value)]u8 {
    var buffer: [int_to_string_len(value)]u8 = undefined; // Enough to hold any 32-bit integer
    _ = std.fmt.bufPrint(buffer[0..], "{}", .{value}) catch unreachable;
    return buffer;
}
