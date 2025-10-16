//! ZonTOM - A cutting-edge TOML library for Zig 0.16.0
//!
//! This library provides a complete TOML 1.0.0 parser with a clean, idiomatic Zig API.
//!
//! Example usage:
//! ```zig
//! const zt = @import("zontom");
//!
//! var table = try zt.parse(allocator, toml_source);
//! defer table.deinit();
//!
//! if (zt.getString(&table, "name")) |name| {
//!     std.debug.print("Name: {s}\n", .{name});
//! }
//! ```

const std = @import("std");

// Re-export public types
pub const Value = @import("value.zig").Value;
pub const Table = @import("value.zig").Table;
pub const Array = @import("value.zig").Array;
pub const Datetime = @import("value.zig").Datetime;
pub const Date = @import("value.zig").Date;
pub const Time = @import("value.zig").Time;
pub const ErrorContext = @import("error.zig").ErrorContext;

// Re-export stringify functions
pub const stringify = @import("stringify.zig").stringify;
pub const stringifyWithOptions = @import("stringify.zig").stringifyWithOptions;
pub const FormatOptions = @import("stringify.zig").FormatOptions;

// Re-export schema validation
pub const Schema = @import("schema.zig").Schema;
pub const SchemaBuilder = @import("schema.zig").SchemaBuilder;
pub const FieldSchema = @import("schema.zig").FieldSchema;
pub const ValueType = @import("schema.zig").ValueType;
pub const Constraint = @import("schema.zig").Constraint;
pub const ValidationResult = @import("schema.zig").ValidationResult;

// Re-export deserialization
pub const parseInto = @import("deserialize.zig").parseInto;
pub const deserialize = @import("deserialize.zig").deserialize;
pub const freeDeserialized = @import("deserialize.zig").free;

// Re-export schema generation
pub const schemaFrom = @import("schema_gen.zig").schemaFrom;

// Re-export conversion functions
pub const toJSON = @import("convert.zig").toJSON;
pub const toJSONPretty = @import("convert.zig").toJSONPretty;

// Re-export diff and merge
pub const diff = @import("diff.zig").diff;
pub const merge = @import("diff.zig").merge;
pub const DiffResult = @import("diff.zig").DiffResult;
pub const Diff = @import("diff.zig").Diff;
pub const DiffType = @import("diff.zig").DiffType;

const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

/// Result of parsing with optional error context
pub const ParseResult = struct {
    table: ?Table,
    error_context: ?ErrorContext,

    pub fn deinit(self: *ParseResult) void {
        if (self.table) |*t| {
            t.deinit();
        }
    }
};

/// Parse TOML source string into a Table
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Table {
    // Tokenize
    var lex = lexer.Lexer.init(allocator, source);
    defer lex.deinit();

    const tokens = try lex.scanTokens();

    // Parse
    var p = parser.Parser.init(allocator, source, tokens);
    defer p.deinit();

    return try p.parse();
}

/// Parse with detailed error context (returns ParseResult with error info)
pub fn parseWithContext(allocator: std.mem.Allocator, source: []const u8) ParseResult {
    var result = ParseResult{
        .table = null,
        .error_context = null,
    };

    // Tokenize
    var lex = lexer.Lexer.init(allocator, source);
    defer lex.deinit();

    const tokens = lex.scanTokens() catch |err| {
        result.error_context = ErrorContext{
            .line = 1,
            .column = 1,
            .source_line = "",
            .message = "Lexer error",
            .suggestion = @errorName(err),
        };
        return result;
    };

    // Parse
    var p = parser.Parser.init(allocator, source, tokens);
    defer p.deinit();

    result.table = p.parse() catch {
        result.error_context = p.getLastError();
        return result;
    };

    return result;
}

/// Get a string value from a table by key
pub fn getString(table: *const Table, key: []const u8) ?[]const u8 {
    const val = table.get(key) orelse return null;
    return switch (val) {
        .string => |s| s,
        else => null,
    };
}

/// Get an integer value from a table by key
pub fn getInt(table: *const Table, key: []const u8) ?i64 {
    const val = table.get(key) orelse return null;
    return switch (val) {
        .integer => |i| i,
        else => null,
    };
}

/// Get a float value from a table by key
pub fn getFloat(table: *const Table, key: []const u8) ?f64 {
    const val = table.get(key) orelse return null;
    return switch (val) {
        .float => |f| f,
        else => null,
    };
}

/// Get a boolean value from a table by key
pub fn getBool(table: *const Table, key: []const u8) ?bool {
    const val = table.get(key) orelse return null;
    return switch (val) {
        .boolean => |b| b,
        else => null,
    };
}

/// Get a table value from a table by key
pub fn getTable(table: *const Table, key: []const u8) ?*const Table {
    const val = table.get(key) orelse return null;
    return switch (val) {
        .table => |t| t,
        else => null,
    };
}

/// Get an array value from a table by key
pub fn getArray(table: *const Table, key: []const u8) ?*const Array {
    const val = table.get(key) orelse return null;
    return switch (val) {
        .array => |*a| a,
        else => null,
    };
}

/// Get a datetime value from a table by key
pub fn getDatetime(table: *const Table, key: []const u8) ?Datetime {
    const val = table.get(key) orelse return null;
    return switch (val) {
        .datetime => |dt| dt,
        else => null,
    };
}

/// Get a value by dotted path (e.g., "server.host.address")
pub fn getPath(table: *const Table, path: []const u8) ?Value {
    var current_table = table;
    var it = std.mem.splitScalar(u8, path, '.');
    var segments = std.ArrayList([]const u8){};
    defer segments.deinit(std.heap.page_allocator);

    // Collect all segments
    while (it.next()) |segment| {
        segments.append(std.heap.page_allocator, segment) catch return null;
    }

    // Navigate through all but the last segment
    for (segments.items[0 .. segments.items.len - 1]) |segment| {
        const val = current_table.get(segment) orelse return null;
        current_table = switch (val) {
            .table => |t| t,
            else => return null,
        };
    }

    // Return the final value
    return current_table.get(segments.items[segments.items.len - 1]);
}

test "parse simple TOML" {
    const testing = std.testing;

    const source =
        \\title = "TOML Example"
        \\
        \\[owner]
        \\name = "Tom Preston-Werner"
    ;

    var table = try parse(testing.allocator, source);
    defer table.deinit();

    const title = getString(&table, "title");
    try testing.expect(title != null);
    try testing.expectEqualStrings("TOML Example", title.?);

    const owner = getTable(&table, "owner");
    try testing.expect(owner != null);

    const owner_name = getString(owner.?, "name");
    try testing.expect(owner_name != null);
    try testing.expectEqualStrings("Tom Preston-Werner", owner_name.?);
}

test "parse with arrays" {
    const testing = std.testing;

    const source = "numbers = [1, 2, 3, 4, 5]";

    var table = try parse(testing.allocator, source);
    defer table.deinit();

    const numbers = getArray(&table, "numbers");
    try testing.expect(numbers != null);
    try testing.expectEqual(@as(usize, 5), numbers.?.items.items.len);
}

test "parse nested tables" {
    const testing = std.testing;

    const source =
        \\[server]
        \\host = "localhost"
        \\port = 8080
        \\
        \\[server.ssl]
        \\enabled = true
    ;

    var table = try parse(testing.allocator, source);
    defer table.deinit();

    const server = getTable(&table, "server");
    try testing.expect(server != null);

    const host = getString(server.?, "host");
    try testing.expectEqualStrings("localhost", host.?);

    const port = getInt(server.?, "port");
    try testing.expectEqual(@as(i64, 8080), port.?);

    const ssl = getTable(server.?, "ssl");
    try testing.expect(ssl != null);

    const enabled = getBool(ssl.?, "enabled");
    try testing.expectEqual(true, enabled.?);
}

test "getPath function" {
    const testing = std.testing;

    const source =
        \\[database]
        \\[database.connection]
        \\host = "localhost"
    ;

    var table = try parse(testing.allocator, source);
    defer table.deinit();

    const host = getPath(&table, "database.connection.host");
    try testing.expect(host != null);
    try testing.expectEqualStrings("localhost", host.?.string);
}
