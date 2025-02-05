const std = @import("std");
const tokens = @import("tokens.zig");
const vm = @import("virtual_machine.zig");

// See exit codes at https://man.freebsd.org/cgi/man.cgi?query=sysexits&apropos=0&sektion=0&manpath=FreeBSD+4.3-RELEASE&format=html
pub const ExitCode = enum(u8) {
    Success = 0,
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
            var tokenizer = tokens.Tokenizer.init(input);
            while (tokenizer.peek() != 0) {
                var buffer: [1024]tokens.Token = undefined;
                const token_count = tokenizer.read_into_buffer(&buffer);
                for (buffer[0..token_count]) |token| {
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

    var tokenizer = tokens.Tokenizer.init(input_buffer);
    while (tokenizer.peek() != 0) {
        var token_buffer: [1024]tokens.Token = undefined;
        const token_count = tokenizer.read_into_buffer(&token_buffer);
        for (token_buffer[0..token_count]) |token| {
            std.debug.print("{}\n", .{token});
        }
    }
}

pub fn main() u8 {
    const allocator = std.heap.page_allocator;
    const args = std.process.argsAlloc(allocator) catch {
        return exit(.OsError);
    };
    defer std.process.argsFree(allocator, args);

    if (args.len == 1) {
        repl(allocator) catch |err| {
            const stderr = std.io.getStdErr();
            stderr.writer().print("Error: {}\n", .{err}) catch {};
            return exit(.SoftwareError);
        };
    } else if (args.len == 2) {
        runFile(allocator, args[1]) catch |err| {
            const stderr = std.io.getStdErr();
            stderr.writer().print("Error: {}\n", .{err}) catch {};
            return exit(.SoftwareError);
        };
    } else {
        const stderr = std.io.getStdErr();
        stderr.writeAll("Usage: orsum [file]\n") catch {};
        return exit(.UsageError); // EX_USAGE
    }

    return exit(.Success);
}
