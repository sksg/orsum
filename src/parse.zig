const std = @import("std");
const tokens = @import("tokens.zig");
const vm = @import("virtual_machine.zig");

const TokenType = tokens.TokenType;

pub const Parser = struct {
    const Self = @This();
    tokens: []const tokens.Token,
    cursor: usize = 0,

    pub fn init(_tokens: []const tokens.Token) Self {
        return Self{ .tokens = _tokens };
    }

    pub fn into(self: *Self, chunk: *vm.IRChunk) !u32 {
        std.debug.print("start parsing...\n", .{});
        const return_register: u32 = @intCast(chunk.new_register());
        var last_expression_register: u32 = undefined;
        while (!self.at_end() and !self.match(.Null)) {
            self.consume_newlines();
            last_expression_register = try self.expression(chunk);
            try self.terminate_expression();
        }
        try chunk.append_instruction(self.current_address(), .Copy, .{
            .source = @intCast(last_expression_register),
            .destination = @intCast(return_register),
        });
        return return_register;
    }

    fn terminate_expression(self: *Self) !void {
        if (self.match(.Newline) or self.match(.Semicolon))
            self.advance()
        else
            return error.ExpressionNotTerminated;
    }

    fn expression(self: *Self, chunk: *vm.IRChunk) !u32 {
        std.debug.print("try expression...\n", .{});
        return self.add_subtract(chunk);
    }

    fn add_subtract(self: *Self, chunk: *vm.IRChunk) !u32 {
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
                    .source_0 = @intCast(source_0),
                    .source_1 = @intCast(source_1),
                    .destination = @intCast(destination),
                });
                source_0 = @intCast(destination);
            } else if (self.match(.Minus)) {
                const address = self.current_address();
                self.advance();
                self.consume_newlines();
                const source_1 = try self.multiply_divide(chunk);
                const destination = chunk.new_register();
                try chunk.append_instruction(address, .Subtract, .{
                    .source_0 = @intCast(source_0),
                    .source_1 = @intCast(source_1),
                    .destination = @intCast(destination),
                });
                source_0 = @intCast(destination);
            } else break;
        }

        return source_0;
    }

    fn multiply_divide(self: *Self, chunk: *vm.IRChunk) !u32 {
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
                    .source_0 = @intCast(source_0),
                    .source_1 = @intCast(source_1),
                    .destination = @intCast(destination),
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
                    .source_0 = @intCast(source_0),
                    .source_1 = @intCast(source_1),
                    .destination = @intCast(destination),
                });
                std.debug.print("consumed '/'...\n", .{});
                source_0 = @intCast(destination);
            } else break;
        }

        return source_0;
    }

    fn negate(self: *Self, chunk: *vm.IRChunk) !u32 {
        std.debug.print("try negate...\n", .{});
        if (self.match(TokenType.Minus)) {
            const address = self.current_address();
            self.advance();
            const source = try self.literal(chunk);
            const destination = chunk.new_register();
            try chunk.append_instruction(address, .Negate, .{
                .source = @intCast(source),
                .destination = @intCast(destination),
            });
            self.advance();
            return @intCast(destination);
        }
        return try self.literal(chunk);
    }

    fn literal(self: *Self, chunk: *vm.IRChunk) !u32 {
        std.debug.print("try literal...\n", .{});
        if (self.match(.IntegerLiteral)) {
            const destination = chunk.new_register();
            const source = try chunk.append_constant(.{ .Integer = try std.fmt.parseInt(i64, tokens.token_lexeme(self.current_token()), 0) });
            try chunk.append_instruction(self.current_address(), .LoadConstant, .{
                .source = @intCast(source),
                .destination = @intCast(destination),
            });
            self.advance();
            return @intCast(destination);
        } else if (self.match(.FloatLiteral)) {
            const destination = chunk.new_register();
            const source = try chunk.append_constant(.{ .FloatingPoint = try std.fmt.parseFloat(f64, tokens.token_lexeme(self.current_token())) });
            try chunk.append_instruction(self.current_address(), .LoadConstant, .{
                .source = @intCast(source),
                .destination = @intCast(destination),
            });
            self.advance();
            return @intCast(destination);
        }
        return error.ExpectedLiteral;
    }

    fn at_end(self: *Self) bool {
        return self.cursor >= self.tokens.len;
    }

    fn match(self: *Self, token_type: TokenType) bool {
        if (self.at_end())
            return false;

        return self.current_token().token_type == token_type;
    }

    fn advance(self: *Self) void {
        std.debug.print("Consumed token: {}\n", .{self.current_token()});
        self.cursor += 1;
    }

    fn consume_newlines(self: *Self) void {
        while (!self.at_end() and self.current_token().token_type == .Newline) {
            self.advance();
        }
    }

    fn current_token(self: *Self) tokens.Token {
        return self.tokens[self.cursor];
    }

    fn current_address(self: *Self) [*]const u8 {
        return self.current_token().lexeme_address;
    }
};
