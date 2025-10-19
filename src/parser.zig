//! TOML parser - builds a table structure from tokens
const std = @import("std");
const lexer = @import("lexer.zig");
const value = @import("value.zig");
const error_mod = @import("error.zig");

const Token = lexer.Token;
const TokenType = lexer.TokenType;
const Value = value.Value;
const Table = value.Table;
const Array = value.Array;

pub const ParseError = error_mod.ParseError;
pub const ErrorContext = error_mod.ErrorContext;

pub const Parser = struct {
    tokens: []const Token,
    current: usize = 0,
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    source: []const u8,
    last_error: ?ErrorContext = null,

    pub fn init(allocator: std.mem.Allocator, source: []const u8, tokens: []const Token) Parser {
        return .{
            .tokens = tokens,
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .source = source,
        };
    }

    pub fn getLastError(self: *const Parser) ?ErrorContext {
        return self.last_error;
    }

    pub fn deinit(self: *Parser) void {
        self.arena.deinit();
    }

    pub fn parse(self: *Parser) !Table {
        var root = Table.init(self.allocator);
        errdefer root.deinit();

        var current_table = &root;
        var table_path = std.ArrayList([]const u8){};
        defer table_path.deinit(self.allocator);

        while (!self.isAtEnd()) {
            // Skip newlines
            while (self.match(.newline)) {}

            if (self.isAtEnd()) break;

            // Check for table headers
            if (self.check(.left_bracket)) {
                _ = self.advance();

                // Check for array of tables [[...]]
                const is_array_table = self.match(.left_bracket);

                // Parse table path
                table_path.clearRetainingCapacity();
                try self.parseTablePath(&table_path);

                if (is_array_table) {
                    if (!self.match(.right_bracket)) {
                        return ParseError.UnexpectedToken;
                    }
                }

                if (!self.match(.right_bracket)) {
                    return ParseError.UnexpectedToken;
                }

                // Navigate/create the table structure
                current_table = try self.getOrCreateTable(&root, table_path.items, is_array_table);
            } else {
                // Parse key-value pair
                try self.parseKeyValue(current_table);
            }

            // Skip trailing newlines
            while (self.match(.newline)) {}
        }

        return root;
    }

    fn parseTablePath(self: *Parser, path: *std.ArrayList([]const u8)) !void {
        const first = try self.consume(.identifier, "Expected table name");
        try path.append(self.allocator, first.lexeme);

        while (self.match(.dot)) {
            const part = try self.consume(.identifier, "Expected identifier after '.'");
            try path.append(self.allocator, part.lexeme);
        }
    }

    fn getOrCreateTable(self: *Parser, root: *Table, path: []const []const u8, is_array: bool) !*Table {
        if (path.len == 0) return root;

        var current = root;
        for (path, 0..) |key, i| {
            const is_last = i == path.len - 1;

            if (current.getPtr(key)) |existing| {
                if (is_last and is_array) {
                    // For array of tables, append new table to array
                    if (existing.* != .array) {
                        return ParseError.InvalidTable;
                    }
                    const new_table = try self.allocator.create(Table);
                    new_table.* = Table.init(self.allocator);
                    try existing.array.items.append(self.allocator, .{ .table = new_table });
                    const last_idx = existing.array.items.items.len - 1;
                    return existing.array.items.items[last_idx].table;
                } else {
                    // Navigate into existing table
                    if (existing.* != .table) {
                        return ParseError.InvalidTable;
                    }
                    current = existing.table;
                }
            } else {
                // Create new table or array of tables
                if (is_last and is_array) {
                    var arr = Array.init(self.allocator);
                    const new_table = try self.allocator.create(Table);
                    new_table.* = Table.init(self.allocator);
                    try arr.items.append(self.allocator, .{ .table = new_table });
                    try current.put(key, .{ .array = arr });
                    const arr_ptr = current.getPtr(key).?;
                    const last_idx = arr_ptr.array.items.items.len - 1;
                    return arr_ptr.array.items.items[last_idx].table;
                } else {
                    const new_table = try self.allocator.create(Table);
                    new_table.* = Table.init(self.allocator);
                    try current.put(key, .{ .table = new_table });
                    current = current.getPtr(key).?.table;
                }
            }
        }

        return current;
    }

    fn parseKeyValue(self: *Parser, table: *Table) !void {
        const key_token = try self.consume(.identifier, "Expected key");
        const key = key_token.lexeme;

        // Handle dotted keys (e.g., a.b.c = value)
        var path = std.ArrayList([]const u8){};
        defer path.deinit(self.allocator);
        try path.append(self.allocator, key);

        while (self.match(.dot)) {
            const part = try self.consume(.identifier, "Expected identifier after '.'");
            try path.append(self.allocator, part.lexeme);
        }

        _ = try self.consume(.equals, "Expected '=' after key");

        const val = try self.parseValue();

        // Navigate to the correct nested table for dotted keys
        var current_table = table;
        for (path.items[0 .. path.items.len - 1]) |segment| {
            if (current_table.getPtr(segment)) |existing| {
                if (existing.* != .table) {
                    return ParseError.InvalidTable;
                }
                current_table = existing.table;
            } else {
                const new_table = try self.allocator.create(Table);
                new_table.* = Table.init(self.allocator);
                try current_table.put(segment, .{ .table = new_table });
                current_table = current_table.getPtr(segment).?.table;
            }
        }

        const final_key = path.items[path.items.len - 1];
        if (current_table.get(final_key)) |_| {
            return ParseError.DuplicateKey;
        }

        try current_table.put(final_key, val);
    }

    fn parseValue(self: *Parser) ParseError!Value {
        const token = self.advance();

        return switch (token.type) {
            .string => .{ .string = try self.parseString(token.lexeme) },
            .integer => .{ .integer = try self.parseInteger(token.lexeme) },
            .float => .{ .float = try self.parseFloat(token.lexeme) },
            .boolean => .{ .boolean = std.mem.eql(u8, token.lexeme, "true") },
            .datetime => try self.parseDatetimeValue(token.lexeme),
            .left_bracket => try self.parseArray(),
            .left_brace => try self.parseInlineTable(),
            else => ParseError.UnexpectedToken,
        };
    }

    fn parseString(self: *Parser, lexeme: []const u8) ![]const u8 {
        // Strip quotes and handle escape sequences
        if (lexeme.len < 2) return ParseError.InvalidValue;

        const quote = lexeme[0];
        const is_literal = (quote == '\'');
        var result = std.ArrayList(u8){};
        defer result.deinit(self.allocator);

        // Check for multi-line strings (triple quotes)
        const is_multiline = lexeme.len >= 6 and lexeme[1] == quote and lexeme[2] == quote;

        if (is_multiline) {
            // Triple-quoted string (multiline)
            var content = lexeme[3 .. lexeme.len - 3];

            // TOML spec: trim first newline after opening quotes if present
            if (content.len > 0 and content[0] == '\n') {
                content = content[1..];
            } else if (content.len > 1 and content[0] == '\r' and content[1] == '\n') {
                content = content[2..];
            }

            if (is_literal) {
                // Multiline literal string - no escape processing
                try result.appendSlice(self.allocator, content);
            } else {
                // Multiline basic string - process escape sequences
                var i: usize = 0;
                while (i < content.len) {
                    if (content[i] == '\\') {
                        i += 1;
                        if (i >= content.len) break;

                        const escaped_char = content[i];
                        switch (escaped_char) {
                            'b' => try result.append(self.allocator, '\x08'),
                            't' => try result.append(self.allocator, '\t'),
                            'n' => try result.append(self.allocator, '\n'),
                            'f' => try result.append(self.allocator, '\x0C'),
                            'r' => try result.append(self.allocator, '\r'),
                            '"' => try result.append(self.allocator, '"'),
                            '\\' => try result.append(self.allocator, '\\'),
                            '\n' => {
                                // Line-ending backslash: trim newline and following whitespace
                                i += 1;
                                while (i < content.len and (content[i] == ' ' or content[i] == '\t' or content[i] == '\n' or content[i] == '\r')) {
                                    i += 1;
                                }
                                i -= 1; // Adjust because loop will increment
                            },
                            '\r' => {
                                // Handle \r\n as line-ending backslash
                                if (i + 1 < content.len and content[i + 1] == '\n') {
                                    i += 2;
                                    while (i < content.len and (content[i] == ' ' or content[i] == '\t' or content[i] == '\n' or content[i] == '\r')) {
                                        i += 1;
                                    }
                                    i -= 1;
                                } else {
                                    try result.append(self.allocator, escaped_char);
                                }
                            },
                            'u', 'U' => {
                                // Unicode escapes - simplified for now, just pass through
                                try result.append(self.allocator, '\\');
                                try result.append(self.allocator, escaped_char);
                            },
                            else => {
                                // Invalid escape - this should have been caught by lexer
                                try result.append(self.allocator, escaped_char);
                            },
                        }
                        i += 1;
                    } else {
                        try result.append(self.allocator, content[i]);
                        i += 1;
                    }
                }
            }
        } else {
            // Single-line string
            const content = lexeme[1 .. lexeme.len - 1];

            if (is_literal) {
                // Literal string - no escape processing
                try result.appendSlice(self.allocator, content);
            } else {
                // Basic string - process escape sequences
                var i: usize = 0;
                while (i < content.len) : (i += 1) {
                    if (content[i] == '\\') {
                        // Handle escape sequences
                        i += 1;
                        if (i >= content.len) break;

                        const escaped = switch (content[i]) {
                            'b' => '\x08',
                            't' => '\t',
                            'n' => '\n',
                            'f' => '\x0C',
                            'r' => '\r',
                            '"' => '"',
                            '\\' => '\\',
                            'u', 'U' => blk: {
                                // Unicode escapes - simplified, just pass through
                                try result.append(self.allocator, '\\');
                                break :blk content[i];
                            },
                            else => content[i],
                        };
                        try result.append(self.allocator, escaped);
                    } else {
                        try result.append(self.allocator, content[i]);
                    }
                }
            }
        }

        // Allocate string using table allocator (will be owned by the table)
        return self.allocator.dupe(u8, result.items);
    }

    fn parseInteger(self: *Parser, lexeme: []const u8) !i64 {
        // Validate and remove underscores per TOML 1.0.0 spec

        // Check for hex/octal/binary (not allowed in TOML)
        if (lexeme.len >= 2) {
            if (lexeme[0] == '0' and (lexeme[1] == 'x' or lexeme[1] == 'X' or
                                      lexeme[1] == 'o' or lexeme[1] == 'O' or
                                      lexeme[1] == 'b' or lexeme[1] == 'B')) {
                return ParseError.InvalidValue; // Hex/octal/binary not allowed
            }
        }

        // Check for leading zeros (not allowed except for "0" itself)
        if (lexeme.len > 1 and lexeme[0] == '0' and std.ascii.isDigit(lexeme[1])) {
            return ParseError.InvalidValue; // Leading zeros not allowed
        }

        // Validate underscore placement
        if (lexeme.len > 0) {
            // Cannot start or end with underscore
            if (lexeme[0] == '_' or lexeme[lexeme.len - 1] == '_') {
                return ParseError.InvalidValue;
            }

            // Check for consecutive underscores and validate placement
            var prev_was_underscore = false;
            for (lexeme) |c| {
                if (c == '_') {
                    if (prev_was_underscore) {
                        return ParseError.InvalidValue; // Consecutive underscores
                    }
                    prev_was_underscore = true;
                } else {
                    prev_was_underscore = false;
                }
            }
        }

        // Remove underscores for parsing
        var cleaned = std.ArrayList(u8){};
        defer cleaned.deinit(self.allocator);

        for (lexeme) |c| {
            if (c != '_' and c != '+') { // Skip underscores and leading +
                try cleaned.append(self.allocator, c);
            }
        }

        return std.fmt.parseInt(i64, cleaned.items, 10) catch ParseError.InvalidValue;
    }

    fn parseFloat(self: *Parser, lexeme: []const u8) !f64 {
        // Handle special float values first
        if (std.mem.eql(u8, lexeme, "inf") or std.mem.eql(u8, lexeme, "+inf")) {
            return std.math.inf(f64);
        }
        if (std.mem.eql(u8, lexeme, "-inf")) {
            return -std.math.inf(f64);
        }
        if (std.mem.eql(u8, lexeme, "nan") or std.mem.eql(u8, lexeme, "+nan") or std.mem.eql(u8, lexeme, "-nan")) {
            return std.math.nan(f64);
        }

        // Validate and remove underscores per TOML 1.0.0 spec

        // Validate underscore placement
        if (lexeme.len > 0) {
            // Cannot start or end with underscore
            if (lexeme[0] == '_' or lexeme[lexeme.len - 1] == '_') {
                return ParseError.InvalidValue;
            }

            // Check for invalid underscore placement
            var prev_was_underscore = false;
            var i: usize = 0;
            while (i < lexeme.len) : (i += 1) {
                const c = lexeme[i];

                if (c == '_') {
                    if (prev_was_underscore) {
                        return ParseError.InvalidValue; // Consecutive underscores
                    }
                    // Underscore cannot be adjacent to decimal point, exponent, or sign
                    if (i > 0) {
                        const prev = lexeme[i - 1];
                        if (prev == '.' or prev == 'e' or prev == 'E' or prev == '+' or prev == '-') {
                            return ParseError.InvalidValue;
                        }
                    }
                    if (i < lexeme.len - 1) {
                        const next = lexeme[i + 1];
                        if (next == '.' or next == 'e' or next == 'E' or next == '+' or next == '-') {
                            return ParseError.InvalidValue;
                        }
                    }
                    prev_was_underscore = true;
                } else {
                    prev_was_underscore = false;
                }
            }
        }

        // Remove underscores for parsing
        var cleaned = std.ArrayList(u8){};
        defer cleaned.deinit(self.allocator);

        for (lexeme) |c| {
            if (c != '_') {
                try cleaned.append(self.allocator, c);
            }
        }

        return std.fmt.parseFloat(f64, cleaned.items) catch ParseError.InvalidValue;
    }

    fn parseDatetimeValue(self: *Parser, lexeme: []const u8) !Value {
        // Determine which datetime type this is based on the format
        // TOML 1.0.0 has four datetime types:
        // 1. Offset Date-Time: 1979-05-27T07:32:00Z or 1979-05-27T07:32:00-07:00
        // 2. Local Date-Time: 1979-05-27T07:32:00
        // 3. Local Date: 1979-05-27
        // 4. Local Time: 07:32:00 or 07:32:00.999999

        // Check if it's just a date (YYYY-MM-DD with length 10)
        if (lexeme.len == 10 and lexeme[4] == '-' and lexeme[7] == '-') {
            return .{ .date = try self.parseDate(lexeme) };
        }

        // Check if it's just a time (HH:MM:SS...)
        if (lexeme.len >= 8 and lexeme[2] == ':' and lexeme[5] == ':') {
            return .{ .time = try self.parseTime(lexeme) };
        }

        // Otherwise it's a full datetime
        return .{ .datetime = try self.parseDatetime(lexeme) };
    }

    fn parseDate(self: *Parser, lexeme: []const u8) !value.Date {
        _ = self;
        if (lexeme.len != 10) return ParseError.InvalidValue;

        const year = std.fmt.parseInt(u16, lexeme[0..4], 10) catch return ParseError.InvalidValue;
        const month = std.fmt.parseInt(u8, lexeme[5..7], 10) catch return ParseError.InvalidValue;
        const day = std.fmt.parseInt(u8, lexeme[8..10], 10) catch return ParseError.InvalidValue;

        // Validate date ranges
        if (month < 1 or month > 12) return ParseError.InvalidValue;
        if (day < 1 or day > 31) return ParseError.InvalidValue;

        // Month-specific day validation
        const days_in_month = [_]u8{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        if (day > days_in_month[month - 1]) return ParseError.InvalidValue;

        return .{ .year = year, .month = month, .day = day };
    }

    fn parseTime(self: *Parser, lexeme: []const u8) !value.Time {
        _ = self;
        if (lexeme.len < 8) return ParseError.InvalidValue;

        const hour = std.fmt.parseInt(u8, lexeme[0..2], 10) catch return ParseError.InvalidValue;
        const minute = std.fmt.parseInt(u8, lexeme[3..5], 10) catch return ParseError.InvalidValue;
        const second = std.fmt.parseInt(u8, lexeme[6..8], 10) catch return ParseError.InvalidValue;

        // Validate time ranges
        if (hour > 23) return ParseError.InvalidValue;
        if (minute > 59) return ParseError.InvalidValue;
        if (second > 60) return ParseError.InvalidValue; // Allow leap second

        var nanosecond: u32 = 0;

        // Parse fractional seconds if present
        if (lexeme.len > 8 and lexeme[8] == '.') {
            var pos: usize = 9;
            const frac_start = pos;

            // Consume all digits
            while (pos < lexeme.len and std.ascii.isDigit(lexeme[pos])) {
                pos += 1;
            }

            if (pos == frac_start) return ParseError.InvalidValue; // Must have at least one digit

            const frac_str = lexeme[frac_start..pos];

            // Convert to nanoseconds (pad or truncate to 9 digits)
            var nanos: u32 = 0;
            var multiplier: u32 = 100_000_000; // Start at 10^8

            for (frac_str, 0..) |c, i| {
                if (i >= 9) break; // Truncate if more than 9 digits
                const digit = c - '0';
                nanos += digit * multiplier;
                multiplier /= 10;
            }

            nanosecond = nanos;

            // Ensure we've consumed the entire string
            if (pos != lexeme.len) return ParseError.InvalidValue;
        }

        return .{ .hour = hour, .minute = minute, .second = second, .nanosecond = nanosecond };
    }

    fn parseDatetime(self: *Parser, lexeme: []const u8) !value.Datetime {
        _ = self;
        // Full RFC3339 datetime parser for TOML 1.0.0

        var dt: value.Datetime = undefined;

        // Parse date part: YYYY-MM-DD
        if (lexeme.len < 10) return ParseError.InvalidValue;

        dt.year = std.fmt.parseInt(u16, lexeme[0..4], 10) catch return ParseError.InvalidValue;
        dt.month = std.fmt.parseInt(u8, lexeme[5..7], 10) catch return ParseError.InvalidValue;
        dt.day = std.fmt.parseInt(u8, lexeme[8..10], 10) catch return ParseError.InvalidValue;

        // Validate date ranges
        if (dt.month < 1 or dt.month > 12) return ParseError.InvalidValue;
        if (dt.day < 1 or dt.day > 31) return ParseError.InvalidValue;

        // Month-specific day validation
        const days_in_month = [_]u8{ 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        if (dt.day > days_in_month[dt.month - 1]) return ParseError.InvalidValue;

        // If there's a time component
        if (lexeme.len > 10 and (lexeme[10] == 'T' or lexeme[10] == 't' or lexeme[10] == ' ')) {
            if (lexeme.len < 19) return ParseError.InvalidValue;

            dt.hour = std.fmt.parseInt(u8, lexeme[11..13], 10) catch return ParseError.InvalidValue;
            dt.minute = std.fmt.parseInt(u8, lexeme[14..16], 10) catch return ParseError.InvalidValue;
            dt.second = std.fmt.parseInt(u8, lexeme[17..19], 10) catch return ParseError.InvalidValue;

            // Validate time ranges
            if (dt.hour > 23) return ParseError.InvalidValue;
            if (dt.minute > 59) return ParseError.InvalidValue;
            if (dt.second > 60) return ParseError.InvalidValue; // Allow leap second

            var pos: usize = 19;

            // Parse fractional seconds if present
            if (pos < lexeme.len and lexeme[pos] == '.') {
                pos += 1;
                const frac_start = pos;

                // Consume all digits
                while (pos < lexeme.len and std.ascii.isDigit(lexeme[pos])) {
                    pos += 1;
                }

                if (pos == frac_start) return ParseError.InvalidValue; // Must have at least one digit

                const frac_str = lexeme[frac_start..pos];

                // Convert to nanoseconds (pad or truncate to 9 digits)
                var nanos: u32 = 0;
                var multiplier: u32 = 100_000_000; // Start at 10^8

                for (frac_str, 0..) |c, i| {
                    if (i >= 9) break; // Truncate if more than 9 digits
                    const digit = c - '0';
                    nanos += digit * multiplier;
                    multiplier /= 10;
                }

                dt.nanosecond = nanos;
            } else {
                dt.nanosecond = 0;
            }

            // Parse timezone offset if present
            if (pos < lexeme.len) {
                const tz_char = lexeme[pos];

                if (tz_char == 'Z' or tz_char == 'z') {
                    // UTC timezone
                    dt.offset_minutes = 0;
                    pos += 1;
                } else if (tz_char == '+' or tz_char == '-') {
                    // Offset timezone: +HH:MM or -HH:MM
                    pos += 1;

                    if (pos + 5 > lexeme.len) return ParseError.InvalidValue;
                    if (lexeme[pos + 2] != ':') return ParseError.InvalidValue;

                    const tz_hour = std.fmt.parseInt(i16, lexeme[pos..pos+2], 10) catch return ParseError.InvalidValue;
                    const tz_min = std.fmt.parseInt(i16, lexeme[pos+3..pos+5], 10) catch return ParseError.InvalidValue;

                    if (tz_hour > 23 or tz_min > 59) return ParseError.InvalidValue;

                    var offset: i16 = tz_hour * 60 + tz_min;
                    if (tz_char == '-') offset = -offset;

                    dt.offset_minutes = offset;
                    pos += 5;
                } else {
                    // No timezone = local time
                    dt.offset_minutes = null;
                }
            } else {
                // No timezone = local time
                dt.offset_minutes = null;
            }

            // Ensure we've consumed the entire string
            if (pos != lexeme.len) return ParseError.InvalidValue;
        } else {
            // Date only - set time to midnight
            dt.hour = 0;
            dt.minute = 0;
            dt.second = 0;
            dt.nanosecond = 0;
            dt.offset_minutes = null;
        }

        return dt;
    }

    fn parseArray(self: *Parser) !Value {
        var arr = Array.init(self.allocator);
        errdefer arr.deinit(self.allocator);

        while (!self.check(.right_bracket) and !self.isAtEnd()) {
            // Skip newlines in arrays
            while (self.match(.newline)) {}
            if (self.check(.right_bracket)) break;

            const val = try self.parseValue();
            try arr.items.append(self.allocator, val);

            // Skip newlines after value
            while (self.match(.newline)) {}

            if (!self.match(.comma)) {
                // Skip newlines before closing bracket
                while (self.match(.newline)) {}
                break;
            }

            // Skip newlines after comma
            while (self.match(.newline)) {}
        }

        _ = try self.consume(.right_bracket, "Expected ']' after array");
        return .{ .array = arr };
    }

    fn parseInlineTable(self: *Parser) !Value {
        const tbl = try self.allocator.create(Table);
        tbl.* = Table.init(self.allocator);
        errdefer {
            tbl.deinit();
            self.allocator.destroy(tbl);
        }

        while (!self.check(.right_brace) and !self.isAtEnd()) {
            const key_token = try self.consume(.identifier, "Expected key in inline table");
            const key = key_token.lexeme;

            _ = try self.consume(.equals, "Expected '=' after key");

            const val = try self.parseValue();
            try tbl.put(key, val);

            if (!self.match(.comma)) break;
        }

        _ = try self.consume(.right_brace, "Expected '}' after inline table");
        return .{ .table = tbl };
    }

    fn match(self: *Parser, token_type: TokenType) bool {
        if (self.check(token_type)) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    fn check(self: *const Parser, token_type: TokenType) bool {
        if (self.isAtEnd()) return false;
        return self.peek().type == token_type;
    }

    fn advance(self: *Parser) Token {
        if (!self.isAtEnd()) self.current += 1;
        return self.previous();
    }

    fn isAtEnd(self: *const Parser) bool {
        return self.peek().type == .eof;
    }

    fn peek(self: *const Parser) Token {
        return self.tokens[self.current];
    }

    fn previous(self: *const Parser) Token {
        return self.tokens[self.current - 1];
    }

    fn consume(self: *Parser, token_type: TokenType, message: []const u8) !Token {
        if (self.check(token_type)) return self.advance();

        const token = self.peek();
        self.last_error = ErrorContext{
            .line = token.line,
            .column = token.column,
            .source_line = error_mod.getSourceLine(self.source, token.line),
            .message = message,
            .suggestion = self.getSuggestion(token_type, token.type),
        };

        return ParseError.UnexpectedToken;
    }

    fn getSuggestion(self: *const Parser, expected: TokenType, got: TokenType) ?[]const u8 {
        _ = self;
        return switch (expected) {
            .identifier => switch (got) {
                .equals => "Did you forget to add a key before the '='?",
                .right_bracket => "Expected a table or array name",
                else => "Expected an identifier (name)",
            },
            .equals => switch (got) {
                .identifier => "Did you mean to use a dot '.' for a nested key?",
                else => "Expected '=' after key",
            },
            .right_bracket => switch (got) {
                .eof => "Missing closing bracket ']'",
                else => "Expected ']' to close table or array",
            },
            .right_brace => switch (got) {
                .eof => "Missing closing brace '}'",
                else => "Expected '}' to close inline table",
            },
            else => null,
        };
    }
};

test "parser basic key-value" {
    const testing = std.testing;

    const source = "name = \"zontom\"\nversion = 1";
    var lex = lexer.Lexer.init(testing.allocator, source);
    defer lex.deinit();

    const tokens = try lex.scanTokens();

    var parser = Parser.init(testing.allocator, source, tokens);
    defer parser.deinit();

    var table = try parser.parse();
    defer table.deinit();

    const name = table.get("name");
    try testing.expect(name != null);
    try testing.expectEqualStrings("zontom", name.?.string);
}

test "parser table" {
    const testing = std.testing;

    const source =
        \\[package]
        \\name = "zontom"
        \\version = 1
    ;

    var lex = lexer.Lexer.init(testing.allocator, source);
    defer lex.deinit();

    const tokens = try lex.scanTokens();

    var parser = Parser.init(testing.allocator, source, tokens);
    defer parser.deinit();

    var table = try parser.parse();
    defer table.deinit();

    const package = table.get("package");
    try testing.expect(package != null);
    try testing.expect(package.?.table.get("name") != null);
}

test "parser array" {
    const testing = std.testing;

    const source = "numbers = [1, 2, 3]";
    var lex = lexer.Lexer.init(testing.allocator, source);
    defer lex.deinit();

    const tokens = try lex.scanTokens();

    var parser = Parser.init(testing.allocator, source, tokens);
    defer parser.deinit();

    var table = try parser.parse();
    defer table.deinit();

    const numbers = table.get("numbers");
    try testing.expect(numbers != null);
    try testing.expectEqual(@as(usize, 3), numbers.?.array.items.items.len);
}

test "parser nested array" {
    const testing = std.testing;

    const source = "data = [[1, 2]]";
    var lex = lexer.Lexer.init(testing.allocator, source);
    defer lex.deinit();

    const tokens = try lex.scanTokens();

    var parser = Parser.init(testing.allocator, source, tokens);
    defer parser.deinit();

    var table = try parser.parse();
    defer table.deinit();

    const data = table.get("data");
    try testing.expect(data != null);
    try testing.expect(data.?.array.items.items.len == 1);
    try testing.expect(data.?.array.items.items[0] == .array);
}
