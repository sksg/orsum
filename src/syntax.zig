const std = @import("std");
const tokens = @import("tokens.zig");
const ir = @import("intermediate_representation.zig");

pub const Token = tokens.Token;
pub const Tokenizer = tokens.Tokenizer;
pub const TokenTracing = tokens.Tracing;

pub const ParserTracing = packed struct {
    consumption: bool = false,
    transition: bool = false,
    production: bool = false,
    with_input: bool = false,

    pub fn any(self: ParserTracing) bool {
        return self.consumption or self.transition or self.production or self.with_input;
    }

    pub const All = ParserTracing{ .consumption = true, .transition = true, .production = true, .with_input = true };
};

pub fn RecursiveDecentParser(TokenizerType: type, tracing: ParserTracing) type {
    return struct {
        const Self = @This();
        const Trace = tracing;
        const TokenBufferSize = 1024;
        const ErrorSet = error{
            StatementNotTerminated,
            ExpectedLiteral,
            ExpectedOperand,
            MissingValidStatement,
            ExpectedOpenParenthesis,
            ExpectedCloseParenthesis,
        };
        const Error = struct {
            err: anyerror,
            token: Token,
            pub fn error_msg(self: Error) []const u8 {
                switch (self.err) {
                    error.StatementNotTerminated => return "expected ';' or newline to a terminate statement",
                    error.ExpectedLiteral => return "expected a literal",
                    error.ExpectedOperand => return "expected an operand",
                    error.MissingValidStatement => return "missing a valid statement",
                    error.ExpectedOpenParenthesis => return "expected '('",
                    error.ExpectedCloseParenthesis => return "expected ')'",
                    else => unreachable,
                }
            }
        };

        tokenizer: *TokenizerType,
        tokens: std.BoundedArray(Token, TokenBufferSize) = std.BoundedArray(Token, TokenBufferSize).init(0) catch unreachable,
        current_token: Token = undefined,
        next_cursor: usize = 0,
        errors: std.BoundedArray(Error, 256) = std.BoundedArray(Error, 256).init(0) catch unreachable,

        pub fn init(tokenizer: *TokenizerType) Self {
            return Self{ .tokenizer = tokenizer };
        }

        pub fn parse(self: *Self, chunk: *ir.Chunk) !void {
            if (Trace.any())
                std.debug.print("PARSER -- begin parsing ..\n", .{});

            if (self.tokens.len == 0)
                self.refill_token_buffer() catch unreachable;

            var had_error = false;

            self.consume_newlines();
            while (!self.at_end()) {
                std.debug.print("PARSER -- Next statement at token {} at {}\n", .{ self.peek(), self.next_cursor });

                self.statement(chunk) catch |err| switch (err) {
                    error.OutOfMemory, error.Overflow, error.InvalidCharacter => return err,
                    inline else => |_err| {
                        if (Trace.transition) {
                            std.debug.print("PARSER -- error {} occurred here {}\n", .{ _err, self.next_token().with_debug_info(self.tokenizer.input) });
                            if (@errorReturnTrace()) |trace|
                                std.debug.dumpStackTrace(trace.*);
                        }

                        try self.errors.append(Error{ .err = _err, .token = self.next_token() });
                        had_error = true;
                        self.recover_from_error();
                    },
                };
                self.consume_newlines();
            }

            if (had_error)
                return error.ParsingFailedWithErrors;
        }

        fn recover_from_error(self: *Self) void {
            if (Trace.transition)
                std.debug.print("PARSER -- recovering from an error ..\n", .{});

            while (!self.at_end()) {
                if (self.peek() == .Null or self.consume_match(.Newline) or self.consume_match(.Semicolon))
                    break;

                self.consume();
            }

            if (Trace.transition)
                std.debug.print("PARSER -- Erroneous tokens hav been consumed\n", .{});
        }

        fn statement(self: *Self, chunk: *ir.Chunk) !void {
            if (Trace.transition)
                std.debug.print("PARSER -- Transistion to statement()\n", .{});

            if (self.advance_match(.Print))
                try self.print(chunk)
            else
                return error.MissingValidStatement;

            if (!self.advance_match(.Newline) and !self.advance_match(.Semicolon) and !(self.peek() == .Null))
                return error.StatementNotTerminated;
        }

        fn print(self: *Self, chunk: *ir.Chunk) !void {
            if (Trace.transition)
                std.debug.print("PARSER -- Transistion to print()\n", .{});

            if (!self.advance_match(.LeftParen))
                return error.ExpectedOpenParenthesis;

            var destination = chunk.new_register();
            try self.expression(chunk, destination);

            if (!self.advance_match(.RightParen))
                return error.ExpectedCloseParenthesis;

            try append_instruction(chunk, self.current_token.address, .Print, .{
                .source = destination.read_access(),
            });
        }

        fn expression(self: *Self, chunk: *ir.Chunk, destination: ir.Register(u8)) !void {
            if (Trace.transition)
                std.debug.print("PARSER -- Transistion to expression()\n", .{});
            return self.comparison(chunk, destination);
        }

        fn comparison(self: *Self, chunk: *ir.Chunk, destination: ir.Register(u8)) !void {
            if (Trace.transition)
                std.debug.print("PARSER -- Transistion to comparison()\n", .{});

            try self.add_subtract(chunk, destination);

            while (!self.at_end()) {
                if (Trace.transition)
                    std.debug.print("PARSER -- Return to comparison()\n", .{});

                if (self.advance_match(.EqualEqual)) {
                    const address = self.current_token.address;
                    const source = chunk.new_register();
                    try self.add_subtract(chunk, source);

                    try append_instruction(chunk, address, .Equal, .{
                        .source_0 = destination.read_access(),
                        .source_1 = source.read_access(),
                        .destination = destination.write_access(),
                    });
                } else if (self.advance_match(.BangEqual)) {
                    const address = self.current_token.address;
                    const source = chunk.new_register();
                    try self.add_subtract(chunk, source);

                    try append_instruction(chunk, address, .NotEqual, .{
                        .source_0 = destination.read_access(),
                        .source_1 = source.read_access(),
                        .destination = destination.write_access(),
                    });
                } else if (self.advance_match(.Lesser)) {
                    const address = self.current_token.address;
                    const source = chunk.new_register();
                    try self.add_subtract(chunk, source);

                    try append_instruction(chunk, address, .LessThan, .{
                        .source_0 = destination.read_access(),
                        .source_1 = source.read_access(),
                        .destination = destination.write_access(),
                    });
                } else if (self.advance_match(.LesserEqual)) {
                    const address = self.current_token.address;
                    const source = chunk.new_register();
                    try self.add_subtract(chunk, source);

                    try append_instruction(chunk, address, .LessThanOrEqual, .{
                        .source_0 = destination.read_access(),
                        .source_1 = source.read_access(),
                        .destination = destination.write_access(),
                    });
                } else if (self.advance_match(.Greater)) {
                    const address = self.current_token.address;
                    const source = chunk.new_register();
                    try self.add_subtract(chunk, source);

                    try append_instruction(chunk, address, .GreaterThan, .{
                        .source_0 = destination.read_access(),
                        .source_1 = source.read_access(),
                        .destination = destination.write_access(),
                    });
                } else if (self.advance_match(.GreaterEqual)) {
                    const address = self.current_token.address;
                    const source = chunk.new_register();
                    try self.add_subtract(chunk, source);

                    try append_instruction(chunk, address, .GreaterThanOrEqual, .{
                        .source_0 = destination.read_access(),
                        .source_1 = source.read_access(),
                        .destination = destination.write_access(),
                    });
                } else break;
            }
        }

        fn add_subtract(self: *Self, chunk: *ir.Chunk, destination: ir.Register(u8)) !void {
            if (Trace.transition)
                std.debug.print("PARSER -- Transistion to add_subtract()\n", .{});

            try self.multiply_divide(chunk, destination);

            while (!self.at_end()) {
                if (Trace.transition)
                    std.debug.print("PARSER -- Return to add_subtract()\n", .{});

                if (self.advance_match(.Plus)) {
                    const address = self.current_token.address;
                    const source = chunk.new_register();
                    try self.multiply_divide(chunk, source);

                    try append_instruction(chunk, address, .Add, .{
                        .source_0 = destination.read_access(),
                        .source_1 = source.read_access(),
                        .destination = destination.write_access(),
                    });
                } else if (self.advance_match(.Minus)) {
                    const address = self.current_token.address;
                    const source = chunk.new_register();
                    try self.multiply_divide(chunk, source);

                    try append_instruction(chunk, address, .Subtract, .{
                        .source_0 = destination.read_access(),
                        .source_1 = source.read_access(),
                        .destination = destination.write_access(),
                    });
                } else break;
            }
        }

        fn multiply_divide(self: *Self, chunk: *ir.Chunk, destination: ir.Register(u8)) !void {
            if (Trace.transition)
                std.debug.print("PARSER -- Transistion to multiply_divide()\n", .{});

            try self.unary(chunk, destination);

            while (!self.at_end()) {
                if (Trace.transition)
                    std.debug.print("PARSER -- Return to multiply_divide()\n", .{});

                if (self.advance_match(.Star)) {
                    const address = self.current_token.address;
                    const source = chunk.new_register();
                    try self.unary(chunk, source);

                    try append_instruction(chunk, address, .Multiply, .{
                        .source_0 = destination.read_access(),
                        .source_1 = source.read_access(),
                        .destination = destination.write_access(),
                    });
                } else if (self.advance_match(.Slash)) {
                    const address = self.current_token.address;
                    const source = chunk.new_register();
                    try self.unary(chunk, source);

                    try append_instruction(chunk, address, .Divide, .{
                        .source_0 = destination.read_access(),
                        .source_1 = source.read_access(),
                        .destination = destination.write_access(),
                    });
                } else break;
            }
        }

        fn unary(self: *Self, chunk: *ir.Chunk, destination: ir.Register(u8)) !void {
            if (Trace.transition)
                std.debug.print("PARSER -- Transistion to unary()\n", .{});

            if (self.advance_match(.Minus)) {
                const address = self.current_token.address;
                self.literal(chunk, destination) catch |err| switch (err) {
                    error.ExpectedLiteral => return error.ExpectedOperand,
                    else => return err,
                };

                if (Trace.transition)
                    std.debug.print("PARSER -- Return to negate()\n", .{});

                try append_instruction(chunk, address, .Negate, .{
                    .source = destination.read_access(),
                    .destination = destination.write_access(),
                });
            } else if (self.advance_match(.Bang)) {
                const address = self.current_token.address;
                self.literal(chunk, destination) catch |err| switch (err) {
                    error.ExpectedLiteral => return error.ExpectedOperand,
                    else => return err,
                };

                if (Trace.transition)
                    std.debug.print("PARSER -- Return to negate()\n", .{});

                try append_instruction(chunk, address, .Not, .{
                    .source = destination.read_access(),
                    .destination = destination.write_access(),
                });
            } else return self.literal(chunk, destination);
        }

        fn literal(self: *Self, chunk: *ir.Chunk, destination: ir.Register(u8)) !void {
            if (Trace.transition)
                std.debug.print("PARSER -- Transistion to literal()\n", .{});

            if (self.advance_match(.IntegerLiteral)) {
                try append_instruction(chunk, self.current_token.address, .LoadConstant, .{
                    .source = try append_constant(chunk, .{ .Integer = try std.fmt.parseInt(i64, self.current_token.lexeme(self.tokenizer.input), 0) }),
                    .destination = destination.write_access(),
                });
            } else if (self.advance_match(.FloatLiteral)) {
                try append_instruction(chunk, self.current_token.address, .LoadConstant, .{
                    .source = try append_constant(chunk, .{ .FloatingPoint = try std.fmt.parseFloat(f64, self.current_token.lexeme(self.tokenizer.input)) }),
                    .destination = destination.write_access(),
                });
            } else if (self.advance_match(.True)) {
                try append_instruction(chunk, self.current_token.address, .LoadConstant, .{
                    .source = try append_constant(chunk, .{ .Boolean = true }),
                    .destination = destination.write_access(),
                });
            } else if (self.advance_match(.False)) {
                try append_instruction(chunk, self.current_token.address, .LoadConstant, .{
                    .source = try append_constant(chunk, .{ .Boolean = false }),
                    .destination = destination.write_access(),
                });
            } else if (self.advance_match(.StringLiteral)) {
                try append_instruction(chunk, self.current_token.address, .LoadConstant, .{
                    .source = try append_constant(chunk, ir.Value.init_from_string_literal(self.current_token.lexeme(self.tokenizer.input))),
                    .destination = destination.write_access(),
                });
            } else return error.ExpectedLiteral;
        }

        fn append_constant(chunk: *ir.Chunk, value: ir.Value) !ir.Constant(u8) {
            const constant = try chunk.append_constant(value);
            if (Trace.production)
                std.debug.print("PARSER -- New constant: [.{s}] {}\n", .{ @tagName(std.meta.activeTag(value)), constant.with_debug_info(chunk.constants.items) });

            return constant;
        }

        fn append_instruction(chunk: *ir.Chunk, address: ir.Address, comptime tag: ir.Instruction.Tag, operands: ir.Instruction.Operands(tag)) !void {
            if (Trace.production)
                std.debug.print("PARSER -- New instruction: {}\n", .{ir.Instruction.init_with_debug_info(tag, operands, null, chunk.constants.items)});

            try chunk.append_instruction(address, tag, operands);
        }

        fn at_end(self: *Self) bool {
            if (Trace.transition)
                std.debug.print("PARSER -- Check for .EndOfFile\n", .{});

            if (self.peek() == .Null)
                return true;

            // Else we need to refill token buffer
            if (self.next_cursor == self.tokens.len) {
                self.refill_token_buffer() catch unreachable;
            }

            return self.peek() == .Null;
        }

        fn refill_token_buffer(self: *Self) !void {
            if (Trace.consumption)
                std.debug.print("PARSER -- Refilling token buffer...\n", .{});

            self.tokens.resize(0) catch unreachable;
            _ = self.tokenizer.read_into_buffer(&self.tokens);
            self.next_cursor = 0;

            if (Trace.consumption)
                std.debug.print("PARSER -- Read {} token(s)\n", .{self.tokens.len});

            if (self.tokens.len == 1)
                return error.UnexpectedTokenRefill;
        }

        fn consume_newlines(self: *Self) void {
            if (Trace.consumption)
                std.debug.print("PARSER -- Consuming newlines\n", .{});

            while (self.peek() == .Newline)
                self.consume();
        }

        fn consume_match(self: *Self, tag: Token.Tag) bool {
            if (self.peek() != tag)
                return false;

            self.consume();
            return true;
        }

        fn advance_match(self: *Self, tag: Token.Tag) bool {
            if (self.peek() != tag)
                return false;

            self.advance();
            return true;
        }

        fn peek(self: *Self) Token.Tag {
            if (self.next_cursor == self.tokens.len)
                unreachable;

            return self.tokens.buffer[self.next_cursor].tag;
        }

        fn next_token(self: *Self) Token {
            if (self.next_cursor == self.tokens.len)
                unreachable;

            return self.tokens.buffer[self.next_cursor];
        }

        fn advance(self: *Self) void {
            if (self.at_end())
                return;

            if (Trace.consumption)
                std.debug.print("PARSER -- Advanced {}\n", .{self.tokens.buffer[self.next_cursor].with_debug_info(self.tokenizer.input)});

            self.current_token = self.tokens.get(self.next_cursor);
            self.next_cursor += 1;
        }

        fn consume(self: *Self) void {
            if (self.at_end())
                return;

            if (Trace.consumption)
                std.debug.print("PARSER -- Consumed {}\n", .{self.tokens.buffer[self.next_cursor].with_debug_info(self.tokenizer.input)});

            if (self.peek() == .Null)
                unreachable;

            self.next_cursor += 1;
        }
    };
}
