const std = @import("std");

const TokenType = enum(u8) {
    Bad,
    EndOfFile,
    // Single characters
    LeftParen = '(',
    RightParen = ')',
    Plus = '+',
    Minus = '-',
    Star = '*',
    Slash = '/',
    Dot = '.',
    Comma = ',',
    Colon = ':',
    Semicolon = ';',
    Newline = '\n',
};

const Token = struct {
    token_type: TokenType,
    lexeme_address: [*]const u8,
};

const Tokenizer = struct {
    input: [:0]const u8,
    cursor: usize,
};

fn read_token(tokenizer: *Tokenizer) Token {
    while (tokenizer.cursor != tokenizer.input.len) {
        const current_address = tokenizer.input.ptr[tokenizer.cursor..];
        const next = current_address[0];
        tokenizer.cursor += 1;
        switch (next) {
            // Skip characters
            ' ', '\t', '\r' => continue,
            // Single characters
            '(', ')', '+', '-', '*', '/', '.', ',', ':', ';', '\n' => return Token{ .token_type = @enumFromInt(next), .lexeme_address = current_address },
            else => return Token{ .token_type = TokenType.Bad, .lexeme_address = current_address },
        }
    }

    return Token{ .token_type = .EndOfFile, .lexeme_address = tokenizer.input.ptr[tokenizer.cursor..] };
}

fn is_alpha_numeric(character: u8) bool {
    return (character >= 'a' and character <= 'z') or (character >= 'A' and character <= 'Z') or (character >= '0' and character <= '9');
}

fn token_lexeme(token: Token) []const u8 {
    return token.lexeme_address[0..1];
}

test "test reading tokens" {
    const input = "() + ()\n";
    var tokenizer = Tokenizer{ .input = input, .cursor = 0 };
    var token = read_token(&tokenizer);
    while (token.token_type != TokenType.EndOfFile) {
        std.debug.print("{}: {s}\n", .{ token.token_type, token_lexeme(token) });
        token = read_token(&tokenizer);
    }
}

// fn consume_char(tokenizer: *Tokenizer, character: u8) bool {
//     if (tokenizer.input[tokenizer.cursor] == character) {
//         tokenizer.cursor += 1;
//         return true;
//     }
//     return false;
// }

// fn consume_slice(tokenizer: *Tokenizer, slice: []const u8) bool {
//     var i: usize = 0;
//     while (i < slice.len) : (i += 1) {
//         if (tokenizer.input[tokenizer.cursor + i] != slice[i]) {
//             return false;
//         }
//     }
//     tokenizer.cursor += slice.len;
//     return true;
// }

// fn consume_integer_literal(tokenizer: *Tokenizer) Token {
//     const start: usize = tokenizer.cursor;
//     while (tokenizer.input[tokenizer.cursor] >= '0' and tokenizer.input[tokenizer.cursor] <= '9') {
//         tokenizer.cursor += 1;
//     }
//     return Token{ .token_type = TokenType.IntegerLiteral, .lexeme_address = tokenizer.input[start..tokenizer.cursor] };
// }
