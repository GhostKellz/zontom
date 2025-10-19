//! TOML lexer - tokenizes TOML source into a stream of tokens
const std = @import("std");

pub const TokenType = enum {
    // Literals
    identifier,
    string,
    integer,
    float,
    boolean,
    datetime,

    // Punctuation
    equals, // =
    comma, // ,
    dot, // .
    left_bracket, // [
    right_bracket, // ]
    left_brace, // {
    right_brace, // }

    // Special
    newline,
    eof,
};

pub const Token = struct {
    type: TokenType,
    lexeme: []const u8,
    line: usize,
    column: usize,
};

pub const LexError = error{
    UnexpectedChar,
    InvalidEscape,
    NumberFormat,
    UnterminatedString,
    OutOfMemory,
};

pub const Lexer = struct {
    source: []const u8,
    start: usize = 0,
    current: usize = 0,
    line: usize = 1,
    column: usize = 1,
    start_line: usize = 1,
    start_column: usize = 1,
    tokens: std.ArrayList(Token),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Lexer {
        return .{
            .source = source,
            .tokens = std.ArrayList(Token){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.tokens.deinit(self.allocator);
    }

    pub fn scanTokens(self: *Lexer) ![]Token {
        while (!self.isAtEnd()) {
            self.start = self.current;
            self.start_line = self.line;
            self.start_column = self.column;
            try self.scanToken();
        }

        try self.tokens.append(self.allocator, .{
            .type = .eof,
            .lexeme = "",
            .line = self.line,
            .column = self.column,
        });

        return self.tokens.items;
    }

    fn scanToken(self: *Lexer) !void {
        const c = self.advance();

        switch (c) {
            ' ', '\t', '\r' => {}, // Skip whitespace
            '\n' => {
                try self.addToken(.newline);
                self.line += 1;
                self.column = 1;
            },
            '#' => self.skipComment(),
            '=' => try self.addToken(.equals),
            ',' => try self.addToken(.comma),
            '.' => {
                // Could be part of a number or a dot separator
                if (self.current > 0 and std.ascii.isDigit(self.source[self.current - 2])) {
                    // This is part of a float, will be handled by number()
                    self.current -= 1;
                    try self.number();
                } else {
                    try self.addToken(.dot);
                }
            },
            '{' => try self.addToken(.left_brace),
            '}' => try self.addToken(.right_brace),
            '[' => try self.addToken(.left_bracket),
            ']' => try self.addToken(.right_bracket),
            '"' => try self.string('"', false),
            '\'' => try self.string('\'', true),
            else => {
                if (std.ascii.isDigit(c) or c == '-' or c == '+') {
                    self.current -= 1;
                    try self.number();
                } else if (std.ascii.isAlphabetic(c) or c == '_') {
                    try self.identifier();
                } else {
                    return LexError.UnexpectedChar;
                }
            },
        }
    }

    fn identifier(self: *Lexer) !void {
        while (!self.isAtEnd() and (std.ascii.isAlphanumeric(self.peek()) or self.peek() == '_' or self.peek() == '-')) {
            _ = self.advance();
        }

        const text = self.source[self.start..self.current];

        // Check for boolean literals
        if (std.mem.eql(u8, text, "true") or std.mem.eql(u8, text, "false")) {
            try self.addToken(.boolean);
        }
        // Check for special float values (inf, nan)
        else if (std.mem.eql(u8, text, "inf") or std.mem.eql(u8, text, "nan")) {
            try self.addToken(.float);
        } else {
            try self.addToken(.identifier);
        }
    }

    fn string(self: *Lexer, quote: u8, literal: bool) !void {
        // Check for multi-line string (triple quotes)
        const is_multiline = self.match(quote) and self.match(quote);

        while (!self.isAtEnd()) {
            const c = self.peek();

            if (is_multiline) {
                // Multi-line: look for three closing quotes
                if (c == quote and self.peekNext() == quote and self.current + 2 < self.source.len and self.source[self.current + 2] == quote) {
                    _ = self.advance(); // First quote
                    _ = self.advance(); // Second quote
                    _ = self.advance(); // Third quote
                    try self.addToken(.string);
                    return;
                }
            } else {
                // Single-line: look for single closing quote or newline
                if (c == quote) {
                    _ = self.advance();
                    try self.addToken(.string);
                    return;
                }
                if (c == '\n') {
                    return LexError.UnterminatedString;
                }
            }

            if (c == '\n') {
                self.line += 1;
                self.column = 0;
            }

            // Handle escape sequences in basic strings (not literal)
            // Both single-line and multiline basic strings support escapes
            if (!literal and c == '\\') {
                _ = self.advance(); // consume backslash
                if (!self.isAtEnd()) {
                    const escaped = self.advance();
                    // Validate escape sequences
                    switch (escaped) {
                        'b', 't', 'n', 'f', 'r', '"', '\\' => {},
                        'u', 'U' => {}, // Unicode escapes - simplified for now
                        '\n' => { // Line-ending backslash in multiline strings
                            if (is_multiline) {
                                // Trim the newline, and will trim leading whitespace on next line in parser
                                self.line += 1;
                                self.column = 0;
                            } else {
                                return LexError.InvalidEscape;
                            }
                        },
                        ' ', '\t' => { // Whitespace after line-ending backslash (allowed in multiline)
                            if (!is_multiline) {
                                return LexError.InvalidEscape;
                            }
                            // In multiline, backslash before whitespace at line end is valid
                            // Continue scanning - whitespace will be trimmed in parser
                        },
                        else => return LexError.InvalidEscape,
                    }
                }
            } else {
                _ = self.advance();
            }
        }

        return LexError.UnterminatedString;
    }

    fn number(self: *Lexer) !void {
        var is_float = false;

        // Handle sign
        const has_sign = self.peek() == '-' or self.peek() == '+';
        if (has_sign) {
            _ = self.advance();
        }

        // Check for special float values: +inf, -inf, +nan, -nan
        if (has_sign and self.current + 3 <= self.source.len) {
            const remaining = self.source[self.current..@min(self.current + 3, self.source.len)];
            if (std.mem.eql(u8, remaining, "inf") or std.mem.eql(u8, remaining, "nan")) {
                self.current += 3;
                try self.addToken(.float);
                return;
            }
        }

        // Check for special date-time pattern (YYYY-MM-DD)
        if (self.current + 10 <= self.source.len) {
            const potential_date = self.source[self.current..@min(self.current + 10, self.source.len)];
            if (self.looksLikeDatetime(potential_date)) {
                try self.datetime();
                return;
            }
        }

        // Check for Local Time pattern (HH:MM:SS)
        if (self.current + 8 <= self.source.len) {
            const potential_time = self.source[self.current..@min(self.current + 8, self.source.len)];
            if (self.looksLikeTime(potential_time)) {
                try self.time();
                return;
            }
        }

        // Integer part
        while (!self.isAtEnd() and (std.ascii.isDigit(self.peek()) or self.peek() == '_')) {
            _ = self.advance();
        }

        // Fractional part
        if (!self.isAtEnd() and self.peek() == '.' and self.current + 1 < self.source.len and std.ascii.isDigit(self.source[self.current + 1])) {
            is_float = true;
            _ = self.advance(); // consume '.'

            while (!self.isAtEnd() and (std.ascii.isDigit(self.peek()) or self.peek() == '_')) {
                _ = self.advance();
            }
        }

        // Exponent part
        if (!self.isAtEnd() and (self.peek() == 'e' or self.peek() == 'E')) {
            is_float = true;
            _ = self.advance();

            if (!self.isAtEnd() and (self.peek() == '+' or self.peek() == '-')) {
                _ = self.advance();
            }

            while (!self.isAtEnd() and (std.ascii.isDigit(self.peek()) or self.peek() == '_')) {
                _ = self.advance();
            }
        }

        try self.addToken(if (is_float) .float else .integer);
    }

    fn looksLikeDatetime(self: *const Lexer, text: []const u8) bool {
        _ = self;
        // Basic check for date pattern: YYYY-MM-DD
        if (text.len >= 10) {
            return std.ascii.isDigit(text[0]) and
                std.ascii.isDigit(text[1]) and
                std.ascii.isDigit(text[2]) and
                std.ascii.isDigit(text[3]) and
                text[4] == '-' and
                std.ascii.isDigit(text[5]) and
                std.ascii.isDigit(text[6]) and
                text[7] == '-' and
                std.ascii.isDigit(text[8]) and
                std.ascii.isDigit(text[9]);
        }
        return false;
    }

    fn looksLikeTime(self: *const Lexer, text: []const u8) bool {
        _ = self;
        // Basic check for time pattern: HH:MM:SS
        if (text.len >= 8) {
            return std.ascii.isDigit(text[0]) and
                std.ascii.isDigit(text[1]) and
                text[2] == ':' and
                std.ascii.isDigit(text[3]) and
                std.ascii.isDigit(text[4]) and
                text[5] == ':' and
                std.ascii.isDigit(text[6]) and
                std.ascii.isDigit(text[7]);
        }
        return false;
    }

    fn datetime(self: *Lexer) !void {
        // Consume date part: YYYY-MM-DD
        while (!self.isAtEnd() and (std.ascii.isDigit(self.peek()) or self.peek() == '-')) {
            _ = self.advance();
        }

        // Check for time part: THH:MM:SS
        if (!self.isAtEnd() and (self.peek() == 'T' or self.peek() == 't' or self.peek() == ' ')) {
            _ = self.advance();

            // Time part
            while (!self.isAtEnd() and (std.ascii.isDigit(self.peek()) or self.peek() == ':' or self.peek() == '.')) {
                _ = self.advance();
            }

            // Optional timezone
            if (!self.isAtEnd() and (self.peek() == 'Z' or self.peek() == 'z' or self.peek() == '+' or self.peek() == '-')) {
                _ = self.advance();
                while (!self.isAtEnd() and (std.ascii.isDigit(self.peek()) or self.peek() == ':')) {
                    _ = self.advance();
                }
            }
        }

        try self.addToken(.datetime);
    }

    fn time(self: *Lexer) !void {
        // Consume time part: HH:MM:SS
        while (!self.isAtEnd() and (std.ascii.isDigit(self.peek()) or self.peek() == ':')) {
            _ = self.advance();
        }

        // Optional fractional seconds
        if (!self.isAtEnd() and self.peek() == '.') {
            _ = self.advance();
            while (!self.isAtEnd() and std.ascii.isDigit(self.peek())) {
                _ = self.advance();
            }
        }

        try self.addToken(.datetime); // Reuse datetime token type
    }

    fn skipComment(self: *Lexer) void {
        while (!self.isAtEnd() and self.peek() != '\n') {
            _ = self.advance();
        }
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.current] != expected) return false;
        self.current += 1;
        self.column += 1;
        return true;
    }

    fn advance(self: *Lexer) u8 {
        const c = self.source[self.current];
        self.current += 1;
        self.column += 1;
        return c;
    }

    fn peek(self: *const Lexer) u8 {
        if (self.isAtEnd()) return 0;
        return self.source[self.current];
    }

    fn peekNext(self: *const Lexer) u8 {
        if (self.current + 1 >= self.source.len) return 0;
        return self.source[self.current + 1];
    }

    fn isAtEnd(self: *const Lexer) bool {
        return self.current >= self.source.len;
    }

    fn addToken(self: *Lexer, token_type: TokenType) !void {
        const lexeme = self.source[self.start..self.current];
        try self.tokens.append(self.allocator, .{
            .type = token_type,
            .lexeme = lexeme,
            .line = self.start_line,
            .column = self.start_column,
        });
    }
};

test "lexer basic tokens" {
    const testing = std.testing;

    const source = "key = \"value\"";
    var lexer = Lexer.init(testing.allocator, source);
    defer lexer.deinit();

    const tokens = try lexer.scanTokens();
    try testing.expectEqual(@as(usize, 4), tokens.len); // key, =, "value", eof
    try testing.expectEqual(TokenType.identifier, tokens[0].type);
    try testing.expectEqual(TokenType.equals, tokens[1].type);
    try testing.expectEqual(TokenType.string, tokens[2].type);
}

test "lexer numbers" {
    const testing = std.testing;

    const source = "int = 42\nfloat = 3.14";
    var lexer = Lexer.init(testing.allocator, source);
    defer lexer.deinit();

    const tokens = try lexer.scanTokens();
    try testing.expect(tokens.len > 6);
    // Should have: int, =, 42, newline, float, =, 3.14, eof
}

test "lexer boolean" {
    const testing = std.testing;

    const source = "enabled = true";
    var lexer = Lexer.init(testing.allocator, source);
    defer lexer.deinit();

    const tokens = try lexer.scanTokens();
    try testing.expectEqual(@as(usize, 4), tokens.len);
    try testing.expectEqual(TokenType.boolean, tokens[2].type);
}

test "lexer table header" {
    const testing = std.testing;

    const source = "[table.name]";
    var lexer = Lexer.init(testing.allocator, source);
    defer lexer.deinit();

    const tokens = try lexer.scanTokens();
    try testing.expectEqual(TokenType.left_bracket, tokens[0].type);
    try testing.expectEqual(TokenType.identifier, tokens[1].type);
    try testing.expectEqual(TokenType.dot, tokens[2].type);
    try testing.expectEqual(TokenType.identifier, tokens[3].type);
    try testing.expectEqual(TokenType.right_bracket, tokens[4].type);
}
