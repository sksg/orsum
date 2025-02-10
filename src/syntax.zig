const std = @import("std");
const tokens = @import("tokens.zig");
const ir = @import("intermediate_representation.zig");

pub const Token = tokens.Token;
pub const Tokenizer = tokens.Tokenizer;

pub const RecursiveDecentParser = struct {
    const Self = @This();
    const TokenBufferSize = 1024;
    tokenizer: *tokens.Tokenizer,
    tokens: [TokenBufferSize]tokens.Token,
    token_count: usize,
    cursor: usize = 0,

    pub fn init(tokenizer: *tokens.Tokenizer) Self {
        return Self{ .tokenizer = tokenizer, .tokens = undefined, .token_count = 0 };
    }

    pub fn parse(self: *Self, chunk: *ir.Chunk) !u32 {
        std.debug.print("start parsing...\n", .{});
        const return_register: u32 = @intCast(chunk.new_register());
        var last_expression_register: u32 = undefined;
        while (!self.at_end() and !self.match(.Null)) {
            self.consume_newlines();
            last_expression_register = try self.expression(chunk);
            try self.terminate_expression();
        }
        try chunk.append_instruction(self.current_address(), .Copy, .{
            .source = ir.register(u8, last_expression_register),
            .destination = ir.register(u8, return_register),
        });
        return return_register;
    }

    fn terminate_expression(self: *Self) !void {
        if (self.match(.Newline) or self.match(.Semicolon))
            self.advance()
        else
            return error.ExpressionNotTerminated;
    }

    fn expression(self: *Self, chunk: *ir.Chunk) !u32 {
        std.debug.print("try expression...\n", .{});
        return self.add_subtract(chunk);
    }

    fn add_subtract(self: *Self, chunk: *ir.Chunk) !u32 {
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
                    .source_0 = ir.register(u8, source_0),
                    .source_1 = ir.register(u8, source_1),
                    .destination = ir.register(u8, destination),
                });
                source_0 = @intCast(destination);
            } else if (self.match(.Minus)) {
                const address = self.current_address();
                self.advance();
                self.consume_newlines();
                const source_1 = try self.multiply_divide(chunk);
                const destination = chunk.new_register();
                try chunk.append_instruction(address, .Subtract, .{
                    .source_0 = ir.register(u8, source_0),
                    .source_1 = ir.register(u8, source_1),
                    .destination = ir.register(u8, destination),
                });
                source_0 = @intCast(destination);
            } else break;
        }

        return source_0;
    }

    fn multiply_divide(self: *Self, chunk: *ir.Chunk) !u32 {
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
                    .source_0 = ir.register(u8, source_0),
                    .source_1 = ir.register(u8, source_1),
                    .destination = ir.register(u8, destination),
                });
                std.debug.print("consumed '*'...\n", .{});
                source_0 = @intCast(destination);
            } else if (self.match(.Slash)) {
                const address = self.current_address();
                self.advance();
                self.consume_newlines();
                const source_1 = try self.negate(chunk);
                const destination = chunk.new_register();
                try chunk.append_instruction(address, .Subtract, .{
                    .source_0 = ir.register(u8, source_0),
                    .source_1 = ir.register(u8, source_1),
                    .destination = ir.register(u8, destination),
                });
                std.debug.print("consumed '/'...\n", .{});
                source_0 = @intCast(destination);
            } else break;
        }

        return source_0;
    }

    fn negate(self: *Self, chunk: *ir.Chunk) !u32 {
        std.debug.print("try negate...\n", .{});
        if (self.match(Token.Minus)) {
            const address = self.current_address();
            self.advance();
            const source = try self.literal(chunk);
            const destination = chunk.new_register();
            try chunk.append_instruction(address, .Negate, .{
                .source = ir.register(u8, source),
                .destination = ir.register(u8, destination),
            });
            self.advance();
            return @intCast(destination);
        }
        return try self.literal(chunk);
    }

    fn literal(self: *Self, chunk: *ir.Chunk) !u32 {
        std.debug.print("try literal...\n", .{});
        if (self.match(.IntegerLiteral)) {
            const destination = chunk.new_register();
            const source = try chunk.append_constant(.{ .Integer = try std.fmt.parseInt(i64, tokens.token_lexeme(self.current_token()), 0) });
            try chunk.append_instruction(self.current_address(), .LoadConstant, .{
                .source = ir.register(u8, source),
                .destination = ir.constant(u8, destination),
            });
            self.advance();
            return @intCast(destination);
        } else if (self.match(.FloatLiteral)) {
            const destination = chunk.new_register();
            const source = try chunk.append_constant(.{ .FloatingPoint = try std.fmt.parseFloat(f64, tokens.token_lexeme(self.current_token())) });
            try chunk.append_instruction(self.current_address(), .LoadConstant, .{
                .source = ir.register(u8, source),
                .destination = ir.constant(u8, destination),
            });
            self.advance();
            return @intCast(destination);
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

        return self.current_token() == tag;
    }

    fn advance(self: *Self) void {
        std.debug.print("Consumed token: {}\n", .{self.current_token()});
        self.cursor += 1;
    }

    fn consume_newlines(self: *Self) void {
        while (!self.at_end() and self.current_token() == .Newline) {
            self.advance();
        }
    }

    fn current_token(self: *Self) tokens.Token {
        return self.tokens[self.cursor];
    }

    fn current_address(self: *Self) [*]const u8 {
        return self.current_token().address();
    }
};
