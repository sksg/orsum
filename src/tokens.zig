const std = @import("std");
const testing = @import("testing.zig");

pub const Token = struct {
    const Self = @This();
    pub const Address = [*]const u8;
    pub const Source = []const u8;

    pub const Tag = enum {
        // Sentinel values
        Null,
        Bad,
        // Single characters
        LeftParen,
        RightParen,
        LeftBrace,
        RightBrace,
        LeftBracket,
        RightBracket,
        Plus,
        Minus,
        Star,
        Slash,
        Dot,
        Comma,
        Colon,
        Semicolon,
        Newline,
        Bang,
        Lesser,
        Equal,
        Greater,
        Ampersand,
        Bar,
        At,
        ColonEqual,
        BangEqual,
        LesserEqual,
        EqualEqual,
        GreaterEqual,
        PlusEqual,
        MinusEqual,
        AmpersandEqual,
        BarEqual,
        PlusPlus,
        MinusMinus,
        AmpersandAmpersand,
        BarBar,
        DotDot,
        DotDotDot,
        // Literals
        IntegerLiteral,
        FloatLiteral,
        StringLiteral,
        True,
        False,
        EndLineComment,
        // Keywords
        Def,
        Import,
        From,
        // Control flow
        If,
        Else,
        For,
        While,
        Do,
        Switch,
        // Identifers
        Identifier,
    };

    pub usingnamespace Tag;

    tag: Tag,
    address: Address,

    pub fn init(comptime tag: Tag, address: Address) Token {
        return Token{ .tag = tag, .address = address };
    }

    pub fn init_from_address(input: Source, address: Address) Token {
        return Tokenizer(.NoTokenizeTrace).init_from_address(input, address).read_token();
    }

    pub fn lexeme(self: Self, input: Source) []const u8 {
        return switch (self.tag) {
            // No lexemes
            .Null => "", // This is the only token without a lexeme (piece of string)
            // Single characters
            .Newline, .LeftParen, .LeftBrace, .LeftBracket, .RightParen, .RightBrace, .RightBracket, .Plus, .Minus, .Star, .Slash, .Dot, .Comma, .Colon, .Semicolon, .Bang, .Lesser, .Equal, .Greater, .Ampersand, .Bar, .At => self.address[0..1],
            // Dual characters
            .ColonEqual, .BangEqual, .LesserEqual, .EqualEqual, .GreaterEqual, .PlusEqual, .PlusPlus, .MinusMinus, .MinusEqual, .AmpersandEqual, .AmpersandAmpersand, .BarEqual, .BarBar, .If, .Do, .DotDot => self.address[0..2],
            // Multi-character
            .Def, .For, .DotDotDot => self.address[0..3],
            .True, .Else, .From => self.address[0..4],
            .False, .While => self.address[0..5],
            .Switch, .Import => self.address[0..6],
            // Unknown length
            .IntegerLiteral => self.address[0..peek_integer_literal_end(input, self.address)],
            .FloatLiteral => self.address[0..peek_float_literal_end(input, self.address)],
            .StringLiteral => self.address[0..peek_string_literal_end(input, self.address)],
            .Identifier => self.address[0..peek_idenifier_end(input, self.address)],
            .EndLineComment => self.address[0..peek_end_line_comment(input, self.address)],
            .Bad => self.address[0..peek_bad_end(input, self.address)],
        };
    }

    pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}{{{s}, {*}}}", .{ @typeName(Self), @tagName(self.tag), self.address });
    }

    pub const WithDebugInfo = struct {
        token: Self,
        input: Self.Source,

        pub fn lexeme(self: WithDebugInfo) []const u8 {
            return self.token.lexeme(self.input);
        }

        pub fn format(self: WithDebugInfo, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("{s}{{{s}, \"{s}\"}}", .{ @typeName(Self), @tagName(self.token.tag), escape_specials(self.lexeme()) });
        }

        pub fn source_line(self: WithDebugInfo) []const u8 {
            var line_begin = self.token.address;
            while (@intFromPtr(line_begin) > @intFromPtr(self.input.ptr) and (line_begin - 1)[0] != '\n') {
                line_begin -= 1;
            }
            var line_length: usize = 0;
            while (@intFromPtr(line_begin + line_length) < @intFromPtr(self.input.ptr + self.input.len) and line_begin[line_length] != '\n') {
                line_length += 1;
            }
            return line_begin[0..line_length];
        }

        pub fn previous_source_lines(self: WithDebugInfo, comptime n: usize) []const u8 {
            var lines_begin = self.token.address;
            while (@intFromPtr(lines_begin) > @intFromPtr(self.input.ptr) and (lines_begin - 1)[0] != '\n') {
                lines_begin -= 1;
            }
            var lines_length: usize = 0;
            var newline_count: usize = 0;
            while (@intFromPtr(lines_begin + lines_length) < @intFromPtr(self.input.ptr + self.input.len) and newline_count < n) {
                lines_begin -= 1;
                lines_length += 1;
                if (lines_begin[0] == '\n')
                    newline_count += 1;
            }
            return lines_begin[0..lines_length];
        }

        pub fn next_source_lines(self: WithDebugInfo, comptime n: usize) []const u8 {
            var lines_begin = self.token.address;
            while (@intFromPtr(lines_begin) < @intFromPtr(self.input.ptr + self.input.len) and lines_begin[0] != '\n') {
                lines_begin += 1;
            }
            var lines_length: usize = 0;
            var newline_count: usize = 0;
            while (@intFromPtr(lines_begin + lines_length) < @intFromPtr(self.input.ptr + self.input.len) and newline_count < n) {
                lines_length += 1;
                if (lines_begin[lines_length] == '\n')
                    newline_count += 1;
            }
            return lines_begin[0..lines_length];
        }

        pub fn column_number(self: WithDebugInfo) usize {
            var line_begin = self.token.address;
            while (@intFromPtr(line_begin) > @intFromPtr(self.input.ptr) and (line_begin - 1)[0] != '\n') {
                line_begin -= 1;
            }
            return 1 + @intFromPtr(self.token.address) - @intFromPtr(line_begin);
        }

        pub fn write_annotation_line(self: WithDebugInfo, writer: anytype, note: []const u8) !void {
            const column = self.column_number();
            const token_len = @max(self.lexeme().len, 1);
            for (0..column - 1) |_| {
                try writer.print(" ", .{});
            }
            for (0..token_len) |_| {
                try writer.print("^", .{});
            }
            try writer.print(" {s}", .{note});
        }

        pub fn line_number(self: WithDebugInfo) usize {
            return 1 + std.mem.count(u8, self.input[0 .. @intFromPtr(self.token.address) - @intFromPtr(self.input.ptr)], "\n");
        }
    };

    pub fn with_debug_info(self: Token, input: Token.Source) WithDebugInfo {
        return WithDebugInfo{ .token = self, .input = input };
    }
};

pub const TokenizerDebugMode = enum { TokenizeTrace, NoTokenizeTrace };

pub fn Tokenizer(debug_mode: TokenizerDebugMode) type {
    return struct {
        const Self = @This();
        const DebugMode = debug_mode;

        input: Token.Source,
        cursor: usize,
        current_lexeme_address: [*]const u8,

        pub fn init(input: Token.Source) Self {
            return Self{
                .input = input,
                .cursor = 0,
                .current_lexeme_address = input.ptr,
            };
        }

        pub fn init_from_address(input: Token.Source, address: Token.Address) Self {
            return Self{
                .input = input,
                .cursor = @intFromPtr(address) - @intFromPtr(input.ptr),
                .current_lexeme_address = address,
            };
        }

        pub fn read_token(self: *Self) Token {
            while (self.cursor < self.input.len) {
                const next = self.first_character();
                switch (next) {
                    // Skip characters
                    ' ', '\t', '\r', 0 => continue,
                    // Single characters
                    inline '(', ')', '{', '}', '[', ']', '*', ',', '\n', ';', '@' => |_next| return self.single_character_token(_next),
                    // Possibly (known) length > 1
                    inline '/' => |_next| return if (self.match_character('/')) self.end_line_comment() else self.single_character_token(_next),
                    inline '.' => |_next| return if (self.match_character('.')) (self.match_token(".", .DotDotDot) orelse self.init_token(.DotDot)) else self.single_character_token(_next),
                    inline ':' => |_next| return self.match_token("=", .ColonEqual) orelse self.single_character_token(_next),
                    inline '!' => |_next| return self.match_token("=", .BangEqual) orelse self.single_character_token(_next),
                    inline '<' => |_next| return self.match_token("=", .LesserEqual) orelse self.single_character_token(_next),
                    inline '=' => |_next| return self.match_token("=", .EqualEqual) orelse self.single_character_token(_next),
                    inline '>' => |_next| return self.match_token("=", .GreaterEqual) orelse self.single_character_token(_next),
                    inline '+' => |_next| return self.match_token("=", .PlusEqual) orelse self.match_token("+", .PlusPlus) orelse self.single_character_token(_next),
                    inline '-' => |_next| return self.match_token("=", .MinusEqual) orelse self.match_token("-", .MinusMinus) orelse self.single_character_token(_next),
                    inline '&' => |_next| return self.match_token("=", .AmpersandEqual) orelse self.match_token("&", .AmpersandAmpersand) orelse self.single_character_token(_next),
                    inline '|' => |_next| return self.match_token("=", .BarEqual) orelse self.match_token("|", .BarBar) orelse self.single_character_token(_next),
                    't' => return self.match_token("rue", .True) orelse self.identifier(),
                    'f' => return self.match_token("alse", .False) orelse self.match_token("or", .For) orelse self.match_token("rom", .From) orelse self.identifier(),
                    'i' => return self.match_token("f", .If) orelse self.match_token("mport", .Import) orelse self.identifier(),
                    'e' => return self.match_token("lse", .Else) orelse self.identifier(),
                    'w' => return self.match_token("hile", .While) orelse self.identifier(),
                    'd' => return self.match_token("o", .Do) orelse self.match_token("ef", .Def) orelse self.identifier(),
                    's' => return self.match_token("witch", .Switch) orelse self.identifier(),
                    // Unknown length
                    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9' => return self.number_literal(),
                    '"' => return self.string_literal(),
                    // Only identifiers left
                    else => return if (is_alpha(next)) self.identifier() else self.bad_token(),
                }
            }

            self.current_lexeme_address = self.input.ptr[self.cursor..];
            return self.null_token();
        }

        pub fn read_into_buffer(self: *Self, buffer: []Token) usize {
            var count: usize = 0;
            while (count < buffer.len) {
                const _token = self.read_token();
                buffer[count] = _token;
                count += 1;
                if (_token.tag == .Null) {
                    break;
                }
            }
            return count;
        }

        pub inline fn peek(self: *Self) u8 {
            if (self.cursor >= self.input.len) {
                return 0;
            }
            return self.input[self.cursor];
        }

        pub inline fn peek_second(self: *Self) u8 {
            if (self.cursor + 1 >= self.input.len) {
                return 0;
            }
            return self.input[self.cursor + 1];
        }

        pub inline fn advance_once(self: *Self) void {
            self.cursor += 1;
        }

        pub fn match_character(self: *Self, comptime character: u8) bool {
            if (self.peek() == character) {
                self.advance_once();
                return true;
            }
            return false;
        }

        pub inline fn first_character(self: *Self) u8 {
            self.current_lexeme_address = self.input.ptr[self.cursor..];
            const _next = self.peek();
            self.advance_once();
            return _next;
        }

        pub inline fn init_token(self: *Self, comptime tag: Token.Tag) Token {
            const token = Token.init(tag, self.current_lexeme_address);
            if (Self.DebugMode == .TokenizeTrace) {
                const debug_info = token.with_debug_info(self.input);
                const stderr = std.io.getStdErr().writer();
                stderr.print("{s}\n", .{debug_info.source_line()}) catch unreachable;
                debug_info.write_annotation_line(stderr, "") catch unreachable;
                stderr.print("(l{}:c{}) {}\n", .{ debug_info.line_number(), debug_info.column_number(), debug_info }) catch unreachable;
            }
            return token;
        }

        pub inline fn single_character_token(self: *Self, comptime character: u8) Token {
            switch (character) {
                '(' => return self.init_token(.LeftParen),
                ')' => return self.init_token(.RightParen),
                '{' => return self.init_token(.LeftBrace),
                '}' => return self.init_token(.RightBrace),
                '[' => return self.init_token(.LeftBracket),
                ']' => return self.init_token(.RightBracket),
                '*' => return self.init_token(.Star),
                ',' => return self.init_token(.Comma),
                ';' => return self.init_token(.Semicolon),
                '\n' => return self.init_token(.Newline),
                '@' => return self.init_token(.At),
                '/' => return self.init_token(.Slash),
                '.' => return self.init_token(.Dot),
                ':' => return self.init_token(.Colon),
                '!' => return self.init_token(.Bang),
                '<' => return self.init_token(.Lesser),
                '=' => return self.init_token(.Equal),
                '>' => return self.init_token(.Greater),
                '+' => return self.init_token(.Plus),
                '-' => return self.init_token(.Minus),
                '&' => return self.init_token(.Ampersand),
                '|' => return self.init_token(.Bar),
                else => @compileError("Character " ++ .{character} ++ " not a 'single character token'!"),
            }
        }

        pub fn match_token(self: *Self, comptime missing: []const u8, comptime tag: Token.Tag) ?Token {
            inline for (missing) |character| {
                if (!self.match_character(character)) {
                    return null;
                }
            }
            return self.init_token(tag);
        }

        pub fn identifier(self: *Self) Token {
            // Here we know that the token must be an identifier, so now we just consume the rest of the identifier
            while (self.cursor < self.input.len and is_alpha_numeric(self.peek()))
                self.advance_once();
            return self.init_token(.Identifier);
        }

        pub inline fn bad_token(self: *Self) Token {
            return self.init_token(.Bad);
        }

        pub inline fn null_token(self: *Self) Token {
            // Since we cannot optimize an optional to use TokenType.Null as null, then we have to use this instead
            return self.init_token(.Null);
        }

        pub fn string_literal(self: *Self) Token {
            while (self.peek() != '"') {
                if (self.peek() == '\n') {
                    return self.init_token(.Bad);
                }
                self.advance_once();
            }
            self.advance_once();
            return self.init_token(.StringLiteral);
        }

        pub fn number_literal(self: *Self) Token {
            var is_float: bool = false;
            var is_bad: bool = false;
            while (is_numeric(self.peek()) or self.peek() == '_') {
                self.advance_once();
            }

            // Try to parse a decimal point
            if (self.peek() == '.' and is_numeric(self.peek_second())) {
                is_float = true;
                self.advance_once(); // Only consume '.' once we know that it is the decimal point
                while (is_numeric(self.peek())) {
                    self.advance_once();
                }
            }

            // Try to parse an exponent
            if ((self.peek() == 'e' or self.peek() == 'E') and (is_numeric(self.peek_second()) or self.peek_second() == '+' or self.peek_second() == '-')) {
                self.advance_once();
                if (self.match_character('+')) {
                    if (self.match_character('-'))
                        is_bad = true;
                } else if (self.match_character('-')) {
                    is_float = true;
                }
                if (!is_numeric(self.peek()))
                    is_bad = true;
                while (is_numeric(self.peek()))
                    self.advance_once();
            }
            if (is_bad) {
                return self.init_token(.Bad);
            } else if (is_float) {
                return self.init_token(.FloatLiteral);
            } else {
                return self.init_token(.IntegerLiteral);
            }
        }

        pub fn end_line_comment(self: *Self) Token {
            while (self.peek() != '\n' and self.peek() != 0) {
                self.advance_once();
            }
            return self.init_token(.EndLineComment);
        }
    };
}

fn is_alpha_numeric(character: u8) bool {
    return (character == '_') or (character >= 'a' and character <= 'z') or (character >= 'A' and character <= 'Z') or (character >= '0' and character <= '9');
}

fn is_alpha(character: u8) bool {
    return (character == '_') or (character >= 'a' and character <= 'z') or (character >= 'A' and character <= 'Z');
}

fn is_numeric(character: u8) bool {
    return (character >= '0' and character <= '9');
}

test "test reading tokens" {
    const input: [339]u8 =
        \\import std.debug
        \\import os from std
        \\
        \\def main() {
        \\    a := 1 + 2.0 * 4e2 / 1_000_000e-2
        \\    b : [_]utf8 = "Hello, World!"[0..6]
        \\    c := true and !false or (1 == 2)
        \\    d := 1 < 2 <= 4
        \\    e := false && true || true
        \\
        \\    f := 1
        \\    f += 2
        \\    f -= 2
        \\    f *= 2
        \\    f /= 2
        \\    f &= 2
        \\    f |= 2
        \\    f++
        \\    f--;
        \\
        \\}  // End of line comments!
    .*;
    var tokenizer = Tokenizer(.TokenizeTrace).init(&input);
    var buffer: [1024]Token = undefined;
    const token_count = tokenizer.read_into_buffer(&buffer);
    for (buffer[0..token_count]) |token| {
        std.debug.print("{}\n", .{token.with_debug_info(&input)});
    }
    var generated: [1024]u8 = undefined;
    var generated_len: usize = 0;
    for (buffer[0..token_count]) |token| {
        const result = std.fmt.bufPrint(generated[generated_len..], "{s} ", .{token.lexeme(&input)}) catch unreachable;
        generated_len += result.len;
        // std.debug.print("{s} ", .{token.lexeme()});
    }
    generated[generated_len] = 0; // null terminate

    const generated_input = generated[0..generated_len :0];

    //std.debug.print("{s}\n", .{generated_input});
    //std.debug.print("Token count: {}\n", .{token_count});

    var alternative_tokenizer = Tokenizer(.TokenizeTrace).init(generated_input);
    var alternative_buffer: [1024]Token = undefined;
    const alternative_token_count = alternative_tokenizer.read_into_buffer(&alternative_buffer);

    try std.testing.expectEqual(token_count, alternative_token_count);

    var debug_buffer: [1024]Token.WithDebugInfo = undefined;
    var debug_alternative_buffer: [1024]Token.WithDebugInfo = undefined;
    for (0..token_count) |i| {
        debug_buffer[i] = buffer[i].with_debug_info(&input);
        debug_alternative_buffer[i] = alternative_buffer[i].with_debug_info(&input);
    }

    try testing.expect_equal_slices(Token.WithDebugInfo, tokens_equal, debug_buffer[0..token_count], debug_alternative_buffer[0..token_count]);
}

fn tokens_equal(left: Token.WithDebugInfo, right: Token.WithDebugInfo) bool {
    return left.token.tag == right.token.tag and strings_equal(left.lexeme(), right.lexeme());
}

fn strings_equal(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, 0..) |left_c, i| {
        if (left_c != right[i]) return false;
    }
    return true;
}

fn escape_specials(string: []const u8) []const u8 {
    return if (strings_equal(string, "\n"[0..1])) "\\n" else if (strings_equal(string, "")) "\\0" else string;
}

fn is_end_of(input: Token.Source, address: [*]const u8, cursor: usize) bool {
    return address + cursor == input.ptr + input.len;
}

fn peek_bad_end(input: Token.Source, start_address: [*]const u8) usize {
    var cursor: usize = 0;
    while (!is_end_of(input, start_address, cursor) and start_address[cursor] != 0) {
        switch (start_address[cursor]) {
            ' ', '\t', '\n' => return cursor,
            else => cursor += 1,
        }
    }
    return cursor;
}

fn peek_idenifier_end(input: Token.Source, start_address: [*]const u8) usize {
    var cursor: usize = 0;
    while (!is_end_of(input, start_address, cursor) and is_alpha_numeric(start_address[cursor])) {
        cursor += 1;
    }
    return cursor;
}

fn peek_string_literal_end(input: Token.Source, start_address: [*]const u8) usize {
    var cursor: usize = 0;
    if (!is_end_of(input, start_address, cursor)) // Assuming a beginning quote '"' is present
        cursor += 1;
    while (!is_end_of(input, start_address, cursor) and start_address[cursor] != '"') {
        cursor += 1;
    }
    if (!is_end_of(input, start_address, cursor)) // Assuming an ending quote '"' is present
        cursor += 1;
    return cursor;
}

fn peek_integer_literal_end(input: Token.Source, start_address: [*]const u8) usize {
    var cursor: usize = 0;
    while (!is_end_of(input, start_address, cursor) and is_numeric(start_address[cursor]) or start_address[cursor] == '_') {
        cursor += 1;
    }
    if (!is_end_of(input, start_address, cursor) and start_address[cursor] == 'e' or start_address[cursor] == 'E') {
        cursor += 1;
        if (!is_end_of(input, start_address, cursor) and start_address[cursor] == '+') {
            cursor += 1;
        }
        while (!is_end_of(input, start_address, cursor) and is_numeric(start_address[cursor]) or start_address[cursor] == '_') {
            cursor += 1;
        }
    }
    return cursor;
}

fn peek_float_literal_end(input: Token.Source, start_address: [*]const u8) usize {
    var cursor: usize = 0;
    while (!is_end_of(input, start_address, cursor) and is_numeric(start_address[cursor]) or start_address[cursor] == '_') {
        cursor += 1;
    }
    if (!is_end_of(input, start_address, cursor) and start_address[cursor] == '.') {
        cursor += 1;
        while (!is_end_of(input, start_address, cursor) and is_numeric(start_address[cursor]) or start_address[cursor] == '_') {
            cursor += 1;
        }
    }
    if (!is_end_of(input, start_address, cursor) and start_address[cursor] == 'e' or start_address[cursor] == 'E') {
        cursor += 1;
        if (!is_end_of(input, start_address, cursor) and start_address[cursor] == '+' or start_address[cursor] == '-') {
            cursor += 1;
        }
        while (!is_end_of(input, start_address, cursor) and is_numeric(start_address[cursor]) or start_address[cursor] == '_') {
            cursor += 1;
        }
    }
    return cursor;
}

fn peek_end_line_comment(input: Token.Source, start_address: [*]const u8) usize {
    var cursor: usize = 0;
    while (!is_end_of(input, start_address, cursor) and start_address[cursor] != '\n' and start_address[cursor] != 0) {
        cursor += 1;
    }
    // Strip trailing whitespace
    while (start_address[cursor - 1] == ' ' or start_address[cursor - 1] == '\t') {
        cursor -= 1;
    }
    return cursor;
}
