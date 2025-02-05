const std = @import("std");
const tokens = @import("tokens.zig");
const vm = @import("virtual_machine.zig");

pub fn main() u8 {
    const allocator = std.heap.page_allocator;
    const args = std.process.argsAlloc(allocator) catch {
        return 71; // EX_OSERR
    };
    defer std.process.argsFree(allocator, args);

    if (args.len == 1) {
        std.debug.print("repl();\n", .{}); // repl();
    } else if (args.len == 2) {
        std.debug.print("runFile(\"{s}\");\n", .{args[1]}); // runFile(args[1]);
    } else {
        const stderr = std.io.getStdErr();
        stderr.writeAll("Usage: orsum [file]\n") catch {};
        return 64; // EX_USAGE
    }

    return 0;
    // See exit codes at https://man.freebsd.org/cgi/man.cgi?query=sysexits&apropos=0&sektion=0&manpath=FreeBSD+4.3-RELEASE&format=html
}
