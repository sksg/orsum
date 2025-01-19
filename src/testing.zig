const std = @import("std");

pub fn expect_equal_slices(comptime T: type, comptime comparator: fn (_: T, _: T) bool, expected: []const T, actual: []const T) !void {
    if (expected.ptr == actual.ptr and expected.len == actual.len) {
        return;
    }
    const diff_index: usize = diff_index: {
        const shortest = @min(expected.len, actual.len);
        var index: usize = 0;
        while (index < shortest) : (index += 1) {
            if (!comparator(actual[index], expected[index])) break :diff_index index;
        }
        break :diff_index if (expected.len == actual.len) return else shortest;
    };

    std.debug.print("slices differ. first difference occurs at index {d} (0x{X})\n", .{ diff_index, diff_index });

    const max_lines: usize = 16;
    const max_window_size: usize = if (T == u8) max_lines * 16 else max_lines;

    // Print a maximum of max_window_size items of each input, starting just before the
    // first difference to give a bit of context.
    var window_start: usize = 0;
    if (@max(actual.len, expected.len) > max_window_size) {
        const alignment = if (T == u8) 16 else 2;
        window_start = std.mem.alignBackward(usize, diff_index - @min(diff_index, alignment), alignment);
    }
    const expected_window = expected[window_start..@min(expected.len, window_start + max_window_size)];
    const expected_truncated = window_start + expected_window.len < expected.len;
    const actual_window = actual[window_start..@min(actual.len, window_start + max_window_size)];
    const actual_truncated = window_start + actual_window.len < actual.len;

    const stderr = std.io.getStdErr();
    const ttyconf = std.io.tty.detectConfig(stderr);
    var differ = if (T == u8) BytesDiffer{
        .expected = expected_window,
        .actual = actual_window,
        .ttyconf = ttyconf,
    } else SliceDiffer(T){
        .start_index = window_start,
        .expected = expected_window,
        .actual = actual_window,
        .ttyconf = ttyconf,
    };

    // Print indexes as hex for slices of u8 since it's more likely to be binary data where
    // that is usually useful.
    const index_fmt = if (T == u8) "0x{X}" else "{}";

    std.debug.print("\n============ expected this output: =============  len: {} (0x{X})\n\n", .{ expected.len, expected.len });
    if (window_start > 0) {
        if (T == u8) {
            std.debug.print("... truncated, start index: " ++ index_fmt ++ " ...\n", .{window_start});
        } else {
            std.debug.print("... truncated ...\n", .{});
        }
    }
    differ.write(stderr.writer()) catch {};
    if (expected_truncated) {
        const end_offset = window_start + expected_window.len;
        const num_missing_items = expected.len - (window_start + expected_window.len);
        if (T == u8) {
            std.debug.print("... truncated, indexes [" ++ index_fmt ++ "..] not shown, remaining bytes: " ++ index_fmt ++ " ...\n", .{ end_offset, num_missing_items });
        } else {
            std.debug.print("... truncated, remaining items: " ++ index_fmt ++ " ...\n", .{num_missing_items});
        }
    }

    // now reverse expected/actual and print again
    differ.expected = actual_window;
    differ.actual = expected_window;
    std.debug.print("\n============= instead found this: ==============  len: {} (0x{X})\n\n", .{ actual.len, actual.len });
    if (window_start > 0) {
        if (T == u8) {
            std.debug.print("... truncated, start index: " ++ index_fmt ++ " ...\n", .{window_start});
        } else {
            std.debug.print("... truncated ...\n", .{});
        }
    }
    differ.write(stderr.writer()) catch {};
    if (actual_truncated) {
        const end_offset = window_start + actual_window.len;
        const num_missing_items = actual.len - (window_start + actual_window.len);
        if (T == u8) {
            std.debug.print("... truncated, indexes [" ++ index_fmt ++ "..] not shown, remaining bytes: " ++ index_fmt ++ " ...\n", .{ end_offset, num_missing_items });
        } else {
            std.debug.print("... truncated, remaining items: " ++ index_fmt ++ " ...\n", .{num_missing_items});
        }
    }
    std.debug.print("\n================================================\n\n", .{});

    return error.TestExpectedEqual;
}

fn SliceDiffer(comptime T: type) type {
    return struct {
        start_index: usize,
        expected: []const T,
        actual: []const T,
        ttyconf: std.io.tty.Config,

        const Self = @This();

        pub fn write(self: Self, writer: anytype) !void {
            for (self.expected, 0..) |value, i| {
                const full_index = self.start_index + i;
                const diff = if (i < self.actual.len) !std.meta.eql(self.actual[i], value) else true;
                if (diff) try self.ttyconf.setColor(writer, .red);
                if (@typeInfo(T) == .Pointer) {
                    try writer.print("[{}]{*}: {any}\n", .{ full_index, value, value });
                } else {
                    try writer.print("[{}]: {any}\n", .{ full_index, value });
                }
                if (diff) try self.ttyconf.setColor(writer, .reset);
            }
        }
    };
}

const BytesDiffer = struct {
    expected: []const u8,
    actual: []const u8,
    ttyconf: std.io.tty.Config,

    pub fn write(self: BytesDiffer, writer: anytype) !void {
        var expected_iterator = std.mem.window(u8, self.expected, 16, 16);
        var row: usize = 0;
        while (expected_iterator.next()) |chunk| {
            // to avoid having to calculate diffs twice per chunk
            var diffs: std.bit_set.IntegerBitSet(16) = .{ .mask = 0 };
            for (chunk, 0..) |byte, col| {
                const absolute_byte_index = col + row * 16;
                const diff = if (absolute_byte_index < self.actual.len) self.actual[absolute_byte_index] != byte else true;
                if (diff) diffs.set(col);
                try self.writeDiff(writer, "{X:0>2} ", .{byte}, diff);
                if (col == 7) try writer.writeByte(' ');
            }
            try writer.writeByte(' ');
            if (chunk.len < 16) {
                var missing_columns = (16 - chunk.len) * 3;
                if (chunk.len < 8) missing_columns += 1;
                try writer.writeByteNTimes(' ', missing_columns);
            }
            for (chunk, 0..) |byte, col| {
                const diff = diffs.isSet(col);
                if (std.ascii.isPrint(byte)) {
                    try self.writeDiff(writer, "{c}", .{byte}, diff);
                } else {
                    // TODO: remove this `if` when https://github.com/ziglang/zig/issues/7600 is fixed
                    if (self.ttyconf == .windows_api) {
                        try self.writeDiff(writer, ".", .{}, diff);
                        continue;
                    }

                    // Let's print some common control codes as graphical Unicode symbols.
                    // We don't want to do this for all control codes because most control codes apart from
                    // the ones that Zig has escape sequences for are likely not very useful to print as symbols.
                    switch (byte) {
                        '\n' => try self.writeDiff(writer, "␊", .{}, diff),
                        '\r' => try self.writeDiff(writer, "␍", .{}, diff),
                        '\t' => try self.writeDiff(writer, "␉", .{}, diff),
                        else => try self.writeDiff(writer, ".", .{}, diff),
                    }
                }
            }
            try writer.writeByte('\n');
            row += 1;
        }
    }

    fn writeDiff(self: BytesDiffer, writer: anytype, comptime fmt: []const u8, args: anytype, diff: bool) !void {
        if (diff) try self.ttyconf.setColor(writer, .red);
        try writer.print(fmt, args);
        if (diff) try self.ttyconf.setColor(writer, .reset);
    }
};
