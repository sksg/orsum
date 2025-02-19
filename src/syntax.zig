const std = @import("std");
const tokens = @import("tokens.zig");
const ir = @import("intermediate_representation.zig");

pub const Token = tokens.Token;
pub const Tokenizer = tokens.Tokenizer;
pub const TokenizerTracingMode = tokens.TokenizerTracingMode;

pub fn RecursiveDecentParser(tokenizer_debug_mode: TokenizerTracingMode) type {
    return struct {
        const Self = @This();
        const TokenBufferSize = 1024;
        tokenizer: *Tokenizer(tokenizer_debug_mode),
        tokens: [TokenBufferSize]tokens.Token,
        token_count: usize,
        cursor: usize = 0,

        pub fn init(tokenizer: *Tokenizer(tokenizer_debug_mode)) Self {
            return Self{ .tokenizer = tokenizer, .tokens = undefined, .token_count = 0 };
        }

        pub fn parse(self: *Self, chunk: *ir.Chunk) !ir.Register(u8) {
            std.debug.print("start parsing...\n", .{});
            const return_register = chunk.new_register();
            var last_expression_register: ir.Register(u8) = undefined;
            while (!self.at_end() and !self.match(.Null)) {
                self.consume_newlines();
                last_expression_register = try self.expression(chunk);
                try self.terminate_expression();
            }
            try chunk.append_instruction(self.current_address(), .Copy, .{
                .source = last_expression_register.read_access(),
                .destination = return_register.write_access(),
            });
            return return_register;
        }

        fn terminate_expression(self: *Self) !void {
            if (self.match(.Newline) or self.match(.Semicolon))
                self.advance()
            else
                return error.ExpressionNotTerminated;
        }

        fn expression(self: *Self, chunk: *ir.Chunk) !ir.Register(u8) {
            std.debug.print("try expression...\n", .{});
            return self.add_subtract(chunk);
        }

        fn add_subtract(self: *Self, chunk: *ir.Chunk) !ir.Register(u8) {
            var source_0 = try self.multiply_divide(chunk);

            std.debug.print("try add_subtract...\n", .{});
            while (!self.at_end()) {
                if (self.match(.Plus)) {
                    const address = self.current_address();
                    self.advance();
                    self.consume_newlines();
                    const source_1 = try self.multiply_divide(chunk);
                    const destination = chunk.new_register();
                    try chunk.append_instruction(address, .Add, .{
                        .source_0 = source_0.read_access(),
                        .source_1 = source_1.read_access(),
                        .destination = destination.write_access(),
                    });
                    source_0 = destination;
                } else if (self.match(.Minus)) {
                    const address = self.current_address();
                    self.advance();
                    self.consume_newlines();
                    const source_1 = try self.multiply_divide(chunk);
                    const destination = chunk.new_register();
                    try chunk.append_instruction(address, .Subtract, .{
                        .source_0 = source_0.read_access(),
                        .source_1 = source_1.read_access(),
                        .destination = destination.write_access(),
                    });
                    source_0 = destination;
                } else break;
            }

            return source_0;
        }

        fn multiply_divide(self: *Self, chunk: *ir.Chunk) !ir.Register(u8) {
            var source_0 = try self.negate(chunk);

            std.debug.print("try multiply_divide...\n", .{});
            while (!self.at_end()) {
                if (self.match(.Star)) {
                    const address = self.current_address();
                    self.advance();
                    self.consume_newlines();
                    const source_1 = try self.negate(chunk);
                    const destination = chunk.new_register();
                    try chunk.append_instruction(address, .Add, .{
                        .source_0 = source_0.read_access(),
                        .source_1 = source_1.read_access(),
                        .destination = destination.write_access(),
                    });
                    std.debug.print("consumed '*'...\n", .{});
                    source_0 = destination;
                } else if (self.match(.Slash)) {
                    const address = self.current_address();
                    self.advance();
                    self.consume_newlines();
                    const source_1 = try self.negate(chunk);
                    const destination = chunk.new_register();
                    try chunk.append_instruction(address, .Subtract, .{
                        .source_0 = source_0.read_access(),
                        .source_1 = source_1.read_access(),
                        .destination = destination.write_access(),
                    });
                    std.debug.print("consumed '/'...\n", .{});
                    source_0 = destination;
                } else break;
            }

            return source_0;
        }

        fn negate(self: *Self, chunk: *ir.Chunk) !ir.Register(u8) {
            std.debug.print("try negate...\n", .{});
            if (self.match(.Minus)) {
                const address = self.current_address();
                self.advance();
                const source = try self.literal(chunk);
                const destination = chunk.new_register();
                try chunk.append_instruction(address, .Negate, .{
                    .source = source.read_access(),
                    .destination = destination.write_access(),
                });
                self.advance();
                return destination;
            }
            return try self.literal(chunk);
        }

        fn literal(self: *Self, chunk: *ir.Chunk) !ir.Register(u8) {
            std.debug.print("try literal...\n", .{});
            if (self.match(.IntegerLiteral)) {
                const destination = chunk.new_register();
                const source = try chunk.append_constant(.{ .Integer = try std.fmt.parseInt(i64, self.current_token().lexeme(self.tokenizer.input), 0) });
                try chunk.append_instruction(self.current_address(), .LoadConstant, .{
                    .source = source,
                    .destination = destination.write_access(),
                });
                self.advance();
                return destination;
            } else if (self.match(.FloatLiteral)) {
                const destination = chunk.new_register();
                const source = try chunk.append_constant(.{ .FloatingPoint = try std.fmt.parseFloat(f64, self.current_token().lexeme(self.tokenizer.input)) });
                try chunk.append_instruction(self.current_address(), .LoadConstant, .{
                    .source = source,
                    .destination = destination.write_access(),
                });
                self.advance();
                return destination;
            }

            return error.ExpectedLiteral;
        }

        fn at_end(self: *Self) bool {
            if (self.cursor >= self.token_count) {
                std.debug.print("Refilling token buffer...\n", .{});
                self.token_count = self.tokenizer.read_into_buffer(&self.tokens);
                self.cursor = 0;
                if (self.token_count == 0)
                    return true;
            }
            return false;
        }

        fn match(self: *Self, tag: Token.Tag) bool {
            if (self.at_end())
                return false;

            return self.current_token().tag == tag;
        }

        fn advance(self: *Self) void {
            std.debug.print("Consumed token: {}\n", .{self.current_token()});
            self.cursor += 1;
        }

        fn consume_newlines(self: *Self) void {
            while (!self.at_end() and self.current_token().tag == .Newline) {
                self.advance();
            }
        }

        fn current_token(self: *Self) tokens.Token {
            return self.tokens[self.cursor];
        }

        fn current_address(self: *Self) [*]const u8 {
            return self.current_token().address;
        }
    };
}
