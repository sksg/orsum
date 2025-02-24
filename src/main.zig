const std = @import("std");
const syntax = @import("syntax.zig");
const ir = @import("intermediate_representation.zig");
const virtual_machine = @import("virtual_machine.zig");

// See POSIX exit codes at https://man.freebsd.org/cgi/man.cgi?query=sysexits&apropos=0&sektion=0&manpath=FreeBSD+4.3-RELEASE&format=html
pub const ExitCode = enum(u8) {
    Success = 0,
    // Exit codes 1-63 are reserved for custom behaviour.
    UsageError = 64,
    SoftwareError = 70,
    OsError = 71,
};

fn exit(code: ExitCode) u8 {
    return @intFromEnum(code);
}

fn repl(allocator: std.mem.Allocator) !void {
    const stdin = std.io.getStdIn().reader();
    const max_line_size = 1024;
    while (true) {
        const maybe_input = try stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', max_line_size);
        if (maybe_input) |input| {
            defer allocator.free(input);
            var tokenizer = syntax.Tokenizer(syntax.TokenTracing.All).init(input);
            while (tokenizer.peek() != 0) {
                var buffer: std.BoundedArray(syntax.Token, 1024) = std.BoundedArray(syntax.Token, 1024).init(0) catch unreachable;
                _ = tokenizer.read_into_buffer(&buffer);
                for (buffer.slice()) |token| {
                    std.debug.print("{}\n", .{token});
                }
            }
        }
    }
}

fn runFile(allocator: std.mem.Allocator, filepath: []const u8) !void {
    const file = try std.fs.cwd().openFile(filepath, .{ .mode = .read_only });
    defer file.close();

    const max_file_size = 1024;
    const input_buffer = try file.readToEndAlloc(allocator, max_file_size);
    defer allocator.free(input_buffer);

    var tokenizer = syntax.Tokenizer(syntax.TokenTracing.All).init(input_buffer);
    var chunk = ir.Chunk.init(allocator);
    var parser = syntax.RecursiveDecentParser(@TypeOf(tokenizer), syntax.ParserTracing.All).init(&tokenizer);
    parser.parse(&chunk) catch |err| switch (err) {
        error.ParsingFailedWithErrors => {
            for (parser.errors.slice()) |_err| {
                const token = _err.token.with_debug_info(input_buffer);

                std.debug.print("{[file]s}:{[line]}:{[column]}: error: {[msg]s}\n", .{
                    .file = filepath,
                    .line = token.line_number(),
                    .column = token.column_number(),
                    .msg = _err.error_msg(),
                });
                std.debug.print("{s}\n", .{token.source_line()});
                token.write_annotation_line(std.io.getStdErr().writer(), "\n") catch unreachable;
            }
            return;
        },
        else => return err,
    };

    var vm = virtual_machine.VirtualMachine(virtual_machine.trace_all).init(allocator, input_buffer);
    defer vm.deinit();

    const exit_code = try vm.interpret(&chunk);
    std.debug.print("Orsum has exited normally with exit-code {}!\n", .{exit_code});
}

pub fn main() u8 {
    const allocator = std.heap.page_allocator;
    const args = std.process.argsAlloc(allocator) catch {
        return exit(.OsError);
    };
    defer std.process.argsFree(allocator, args);

    if (args.len == 1) {
        repl(allocator) catch |err| {
            const trace = @errorReturnTrace();
            const stderr = std.io.getStdErr();
            stderr.writer().print("Error: {} {}\n", .{ err, trace.? }) catch {};

            return exit(.SoftwareError);
        };
    } else if (args.len == 2) {
        runFile(allocator, args[1]) catch |err| {
            const trace = @errorReturnTrace();
            const stderr = std.io.getStdErr();
            stderr.writer().print("Error: {}\n", .{err}) catch {};
            stderr.writer().print("Error: {} {}\n", .{ err, trace.? }) catch {};
            return exit(.SoftwareError);
        };
    } else {
        const stderr = std.io.getStdErr();
        stderr.writeAll("Usage: orsum [file]\n") catch {};
        return exit(.UsageError); // EX_USAGE
    }

    return exit(.Success);
}
