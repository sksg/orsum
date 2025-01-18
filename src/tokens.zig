const std = @import("std");

const TokenType = enum(u8) {
    // Single characters
    LeftParen = '(',
    RightParen = ')',
    LeftBrace = '{',
    RightBrace = '}',
    LeftBracket = '[',
    RightBracket = ']',
    Plus = '+',
    Minus = '-',
    Star = '*',
    Slash = '/',
    Dot = '.',
    Comma = ',',
    Colon = ':',
    Semicolon = ';',
    Newline = '\n',
    NullTerminator = 0,
    Bang = '!',
    Lesser = '<',
    Equal = '=',
    Greater = '>',
    Ampersand = '&',
    Bar = '|',
    At = '@',
    // Dual characters (cannot be sum of two single characters due to clashing with other tokens)
    ColonEqual = 128, // = (':' + '='),
    BangEqual, // = ('!' + '='),
    LesserEqual, // = ('<' + '='),
    EqualEqual, // = ('=' + '='),
    GreaterEqual, // = ('>' + '='),
    PlusEqual, // = ('+' + '='),
    MinusEqual, // = ('-' + '='),
    AmpersandEqual, // = ('&' + '='),
    BarEqual, // = ('|' + '='),
    PlusPlus, // = ('+' + '+'),
    MinusMinus, // = ('-' + '-'),
    AmpersandAmpersand, // = ('&' + '&'),
    BarBar, // = ('|' + '|'),
    DotDot, // = ('.' + '.'),
    DotDotDot, // = ('.' + '.' + '.'),
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
    // Sentinel values
    Bad,
};

const Token = struct {
    token_type: TokenType,
    lexeme_address: [*]const u8,

    pub fn init(token_type: TokenType, lexeme_address: [*]const u8) Token {
        return .{ .token_type = token_type, .lexeme_address = lexeme_address };
    }
};

const Tokenizer = struct {
    input: [:0]const u8,
    cursor: usize,
    current_lexeme_address: [*]const u8,

    pub fn init(input: [:0]const u8) Tokenizer {
        return Tokenizer{
            .input = input,
            .cursor = 0,
            .current_lexeme_address = input.ptr[0..],
        };
    }

    pub inline fn peek(self: *Tokenizer) u8 {
        return self.input[self.cursor];
    }

    pub inline fn peek_second(self: *Tokenizer) u8 {
        return self.input[self.cursor + 1];
    }

    pub inline fn advance_once(self: *Tokenizer) void {
        self.cursor += 1;
    }

    pub fn match_character(self: *Tokenizer, comptime character: u8) bool {
        if (self.peek() == character) {
            self.advance_once();
            return true;
        }
        return false;
    }

    pub inline fn first_character(self: *Tokenizer) u8 {
        self.current_lexeme_address = self.input.ptr[self.cursor..];
        const _next = self.peek();
        self.advance_once();
        return _next;
    }

    pub inline fn token(self: *Tokenizer, comptime token_type: TokenType) Token {
        return Token.init(token_type, self.current_lexeme_address);
    }

    pub fn single_character_token(self: *Tokenizer, character: u8) Token {
        return Token.init(@enumFromInt(character), self.current_lexeme_address);
    }

    pub fn match_token(self: *Tokenizer, comptime missing: []const u8, comptime token_type: TokenType) ?Token {
        inline for (missing) |character| {
            if (!self.match_character(character)) {
                return null;
            }
        }
        return Token.init(token_type, self.current_lexeme_address);
    }

    pub fn identifier(self: *Tokenizer) Token {
        // Here we know that the token must be an identifier, so now we just consume the rest of the identifier
        while (is_alpha_numeric(self.peek()))
            self.advance_once();
        return Token.init(.Identifier, self.current_lexeme_address);
    }

    pub inline fn bad_token(self: *Tokenizer) Token {
        return Token.init(.Bad, self.current_lexeme_address);
    }

    pub fn string_literal(self: *Tokenizer) Token {
        while (self.peek() != '"') {
            if (self.peek() == '\n') {
                return Token.init(.Bad, self.current_lexeme_address);
            }
            self.advance_once();
        }
        self.advance_once();
        return Token.init(.StringLiteral, self.current_lexeme_address);
    }

    pub fn number_literal(self: *Tokenizer) Token {
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
        return Token.init(if (is_bad) .Bad else (if (is_float) .FloatLiteral else .IntegerLiteral), self.current_lexeme_address);
    }

    pub fn end_line_comment(self: *Tokenizer) Token {
        while (self.peek() != '\n' and self.peek() != 0) {
            self.advance_once();
        }
        return Token.init(.EndLineComment, self.current_lexeme_address);
    }

    pub fn read_token(self: *Tokenizer) ?Token {
        while (self.cursor != self.input.len + 1) { // Count the null terminator as well
            const next = self.first_character();
            switch (next) {
                // Skip characters
                ' ', '\t', '\r' => continue,
                // Single characters
                '(', ')', '{', '}', '[', ']', '*', ',', ';', '\n', '@', 0 => return self.single_character_token(next),
                // Possibly (known) length > 1
                '/' => return if (self.match_character('/')) self.end_line_comment() else self.single_character_token(next),
                '.' => return if (self.match_character('.')) (self.match_token(".", .DotDotDot) orelse self.token(.DotDot)) else self.single_character_token(next),
                ':' => return self.match_token("=", .ColonEqual) orelse self.single_character_token(next),
                '!' => return self.match_token("=", .BangEqual) orelse self.single_character_token(next),
                '<' => return self.match_token("=", .LesserEqual) orelse self.single_character_token(next),
                '=' => return self.match_token("=", .EqualEqual) orelse self.single_character_token(next),
                '>' => return self.match_token("=", .GreaterEqual) orelse self.single_character_token(next),
                '+' => return self.match_token("=", .PlusEqual) orelse self.match_token("+", .PlusPlus) orelse self.single_character_token(next),
                '-' => return self.match_token("=", .MinusEqual) orelse self.match_token("-", .MinusMinus) orelse self.single_character_token(next),
                '&' => return self.match_token("=", .AmpersandEqual) orelse self.match_token("&", .AmpersandAmpersand) orelse self.single_character_token(next),
                '|' => return self.match_token("=", .BarEqual) orelse self.match_token("|", .BarBar) orelse self.single_character_token(next),
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

        return null;
    }
};

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
    const input =
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
    ;
    var tokenizer = Tokenizer.init(input);
    while (tokenizer.read_token()) |token| {
        std.debug.print("{}: {s}\n", .{ token.token_type, escape_specials(token_lexeme(token)) });
    }
    tokenizer = Tokenizer.init(input);
    while (tokenizer.read_token()) |token| {
        std.debug.print("{s} ", .{token_lexeme(token)});
    }
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

fn token_lexeme(token: Token) []const u8 {
    return switch (token.token_type) {
        // Sentinel values
        .NullTerminator => token.lexeme_address[0..0],
        // Single characters
        .Newline, .LeftParen, .LeftBrace, .LeftBracket, .RightParen, .RightBrace, .RightBracket, .Plus, .Minus, .Star, .Slash, .Dot, .Comma, .Colon, .Semicolon, .Bang, .Lesser, .Equal, .Greater, .Ampersand, .Bar, .At => token.lexeme_address[0..1],
        // Dual characters
        .ColonEqual, .BangEqual, .LesserEqual, .EqualEqual, .GreaterEqual, .PlusEqual, .PlusPlus, .MinusMinus, .MinusEqual, .AmpersandEqual, .AmpersandAmpersand, .BarEqual, .BarBar, .If, .Do, .DotDot => token.lexeme_address[0..2],
        // Multi-character
        .Def, .For, .DotDotDot => token.lexeme_address[0..3],
        .True, .Else, .From => token.lexeme_address[0..4],
        .False, .While => token.lexeme_address[0..5],
        .Switch, .Import => token.lexeme_address[0..6],
        // Unknown length
        .IntegerLiteral => token.lexeme_address[0..peek_integer_literal_end(token.lexeme_address)],
        .FloatLiteral => token.lexeme_address[0..peek_float_literal_end(token.lexeme_address)],
        .StringLiteral => token.lexeme_address[0..peek_string_literal_end(token.lexeme_address)],
        .Identifier => token.lexeme_address[0..peek_idenifier_end(token.lexeme_address)],
        .EndLineComment => token.lexeme_address[0..peek_end_line_comment(token.lexeme_address)],
        .Bad => token.lexeme_address[0..peek_bad_end(token.lexeme_address)],
    };
}

fn peek_bad_end(start_address: [*]const u8) usize {
    var cursor: usize = 0;
    while (start_address[cursor] != 0) {
        switch (start_address[cursor]) {
            ' ', '\t', '\n' => return cursor,
            else => cursor += 1,
        }
    }
    return cursor;
}

fn peek_idenifier_end(start_address: [*]const u8) usize {
    var cursor: usize = 0;
    while (is_alpha_numeric(start_address[cursor])) {
        cursor += 1;
    }
    return cursor;
}

fn peek_string_literal_end(start_address: [*]const u8) usize {
    var cursor: usize = 0;
    cursor += 1;
    while (start_address[cursor] != '"') {
        cursor += 1;
    }
    cursor += 1;
    return cursor;
}

fn peek_integer_literal_end(start_address: [*]const u8) usize {
    var cursor: usize = 0;
    while (is_numeric(start_address[cursor]) or start_address[cursor] == '_') {
        cursor += 1;
    }
    if (start_address[cursor] == 'e' or start_address[cursor] == 'E') {
        cursor += 1;
        if (start_address[cursor] == '+') {
            cursor += 1;
        }
        while (is_numeric(start_address[cursor]) or start_address[cursor] == '_') {
            cursor += 1;
        }
    }
    return cursor;
}

fn peek_float_literal_end(start_address: [*]const u8) usize {
    var cursor: usize = 0;
    while (is_numeric(start_address[cursor]) or start_address[cursor] == '_') {
        cursor += 1;
    }
    if (start_address[cursor] == '.') {
        cursor += 1;
        while (is_numeric(start_address[cursor]) or start_address[cursor] == '_') {
            cursor += 1;
        }
    }
    if (start_address[cursor] == 'e' or start_address[cursor] == 'E') {
        cursor += 1;
        if (start_address[cursor] == '+' or start_address[cursor] == '-') {
            cursor += 1;
        }
        while (is_numeric(start_address[cursor]) or start_address[cursor] == '_') {
            cursor += 1;
        }
    }
    return cursor;
}

fn peek_end_line_comment(start_address: [*]const u8) usize {
    var cursor: usize = 0;
    while (start_address[cursor] != '\n' and start_address[cursor] != 0) {
        cursor += 1;
    }
    return cursor;
}
