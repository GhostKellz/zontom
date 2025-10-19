//! TOML stringification - convert Table back to TOML format
const std = @import("std");
const value = @import("value.zig");

const Value = value.Value;
const Table = value.Table;
const Array = value.Array;

pub const StringifyError = error{
    OutOfMemory,
    InvalidValue,
};

pub const FormatOptions = struct {
    /// Indent size for nested structures
    indent: usize = 2,
    /// Use spaces instead of tabs
    use_spaces: bool = true,
    /// Add blank lines between sections
    blank_lines: bool = true,
    /// Sort keys alphabetically
    sort_keys: bool = false,
    /// Inline tables for short tables (max keys)
    inline_table_threshold: usize = 3,
};

pub const Stringifier = struct {
    allocator: std.mem.Allocator,
    options: FormatOptions,
    output: std.ArrayList(u8),
    current_indent: usize,

    pub fn init(allocator: std.mem.Allocator, options: FormatOptions) Stringifier {
        return .{
            .allocator = allocator,
            .options = options,
            .output = std.ArrayList(u8){},
            .current_indent = 0,
        };
    }

    pub fn deinit(self: *Stringifier) void {
        self.output.deinit(self.allocator);
    }

    pub fn stringify(self: *Stringifier, table: *const Table) ![]const u8 {
        try self.stringifyTable(table, &.{});
        return self.output.items;
    }

    fn stringifyTable(self: *Stringifier, table: *const Table, path: []const []const u8) !void {
        var keys = std.ArrayList([]const u8){};
        defer keys.deinit(self.allocator);

        // Collect all keys
        var it = table.map.iterator();
        while (it.next()) |entry| {
            try keys.append(self.allocator, entry.key_ptr.*);
        }

        // Sort if requested
        if (self.options.sort_keys) {
            std.sort.block([]const u8, keys.items, {}, struct {
                fn lessThan(_: void, a: []const u8, b: []const u8) bool {
                    return std.mem.order(u8, a, b) == .lt;
                }
            }.lessThan);
        }

        // First pass: write simple key-value pairs
        var first_value = true;
        for (keys.items) |key| {
            const val = table.map.get(key).?;

            // Skip tables and arrays of tables for first pass
            if (val == .table) continue;
            if (val == .array) {
                // Check if it's an array of tables
                if (val.array.items.items.len > 0 and val.array.items.items[0] == .table) {
                    continue;
                }
            }

            if (!first_value and self.options.blank_lines and path.len == 0) {
                // Don't add blank lines for simple values
            }
            first_value = false;

            try self.writeIndent();
            try self.writeKey(key);
            try self.output.appendSlice(self.allocator, " = ");
            try self.writeValue(&val);
            try self.output.append(self.allocator, '\n');
        }

        // Second pass: write tables
        var first_table = true;
        for (keys.items) |key| {
            const val = table.map.get(key).?;

            if (val != .table) continue;

            if (!first_table and self.options.blank_lines) {
                try self.output.append(self.allocator, '\n');
            }
            first_table = false;

            // Build new path
            var new_path = std.ArrayList([]const u8){};
            defer new_path.deinit(self.allocator);
            try new_path.appendSlice(self.allocator, path);
            try new_path.append(self.allocator, key);

            // Write table header
            if (new_path.items.len > 0) {
                try self.output.append(self.allocator, '[');
                for (new_path.items, 0..) |segment, i| {
                    if (i > 0) try self.output.append(self.allocator, '.');
                    try self.writeKey(segment);
                }
                try self.output.appendSlice(self.allocator, "]\n");
            }

            try self.stringifyTable(val.table, new_path.items);
        }

        // Third pass: write array of tables
        for (keys.items) |key| {
            const val = table.map.get(key).?;

            if (val != .array) continue;
            if (val.array.items.items.len == 0) continue;
            if (val.array.items.items[0] != .table) continue;

            // Build new path
            var new_path = std.ArrayList([]const u8){};
            defer new_path.deinit(self.allocator);
            try new_path.appendSlice(self.allocator, path);
            try new_path.append(self.allocator, key);

            // Write each table in the array
            for (val.array.items.items) |item| {
                if (self.options.blank_lines) {
                    try self.output.append(self.allocator, '\n');
                }

                try self.output.appendSlice(self.allocator, "[[");
                for (new_path.items, 0..) |segment, i| {
                    if (i > 0) try self.output.append(self.allocator, '.');
                    try self.writeKey(segment);
                }
                try self.output.appendSlice(self.allocator, "]]\n");

                try self.stringifyTable(item.table, new_path.items);
            }
        }
    }

    fn writeValue(self: *Stringifier, val: *const Value) !void {
        switch (val.*) {
            .string => |s| try self.writeString(s),
            .integer => |i| try self.output.writer(self.allocator).print("{d}", .{i}),
            .float => |f| {
                if (std.math.isNan(f)) {
                    try self.output.appendSlice(self.allocator, "nan");
                } else if (std.math.isPositiveInf(f)) {
                    try self.output.appendSlice(self.allocator, "inf");
                } else if (std.math.isNegativeInf(f)) {
                    try self.output.appendSlice(self.allocator, "-inf");
                } else {
                    try self.output.writer(self.allocator).print("{d}", .{f});
                }
            },
            .boolean => |b| try self.output.appendSlice(self.allocator, if (b) "true" else "false"),
            .datetime => |dt| try self.writeDatetime(dt),
            .date => |d| try self.writeDate(d),
            .time => |t| try self.writeTime(t),
            .array => |*arr| try self.writeArray(arr),
            .table => |tbl| try self.writeInlineTable(tbl),
        }
    }

    fn writeString(self: *Stringifier, s: []const u8) !void {
        try self.output.append(self.allocator, '"');

        for (s) |c| {
            switch (c) {
                '"' => try self.output.appendSlice(self.allocator, "\\\""),
                '\\' => try self.output.appendSlice(self.allocator, "\\\\"),
                '\n' => try self.output.appendSlice(self.allocator, "\\n"),
                '\r' => try self.output.appendSlice(self.allocator, "\\r"),
                '\t' => try self.output.appendSlice(self.allocator, "\\t"),
                '\x08' => try self.output.appendSlice(self.allocator, "\\b"),
                '\x0C' => try self.output.appendSlice(self.allocator, "\\f"),
                else => try self.output.append(self.allocator, c),
            }
        }

        try self.output.append(self.allocator, '"');
    }

    fn writeDatetime(self: *Stringifier, dt: value.Datetime) !void {
        const writer = self.output.writer(self.allocator);
        try writer.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
            dt.year, dt.month, dt.day,
            dt.hour, dt.minute, dt.second,
        });

        if (dt.offset_minutes) |offset| {
            const sign: u8 = if (offset < 0) '-' else '+';
            const abs_offset: u16 = @abs(offset);
            const hours = abs_offset / 60;
            const minutes = abs_offset % 60;
            try writer.print("{c}{d:0>2}:{d:0>2}", .{ sign, hours, minutes });
        } else {
            try writer.writeAll("Z");
        }
    }

    fn writeDate(self: *Stringifier, d: value.Date) !void {
        const writer = self.output.writer(self.allocator);
        try writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ d.year, d.month, d.day });
    }

    fn writeTime(self: *Stringifier, t: value.Time) !void {
        const writer = self.output.writer(self.allocator);
        try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ t.hour, t.minute, t.second });
    }

    fn writeArray(self: *Stringifier, arr: *const Array) !void {
        try self.output.append(self.allocator, '[');

        for (arr.items.items, 0..) |item, i| {
            if (i > 0) try self.output.appendSlice(self.allocator, ", ");
            try self.writeValue(&item);
        }

        try self.output.append(self.allocator, ']');
    }

    fn writeInlineTable(self: *Stringifier, tbl: *const Table) !void {
        try self.output.appendSlice(self.allocator, "{ ");

        var it = tbl.map.iterator();
        var first = true;
        while (it.next()) |entry| {
            if (!first) try self.output.appendSlice(self.allocator, ", ");
            first = false;

            try self.writeKey(entry.key_ptr.*);
            try self.output.appendSlice(self.allocator, " = ");
            try self.writeValue(entry.value_ptr);
        }

        try self.output.appendSlice(self.allocator, " }");
    }

    fn writeKey(self: *Stringifier, key: []const u8) !void {
        // Check if key needs quoting
        const needs_quotes = for (key) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_' and c != '-') {
                break true;
            }
        } else false;

        if (needs_quotes) {
            try self.writeString(key);
        } else {
            try self.output.appendSlice(self.allocator, key);
        }
    }

    fn writeIndent(self: *Stringifier) !void {
        const indent_char: u8 = if (self.options.use_spaces) ' ' else '\t';
        const indent_size = if (self.options.use_spaces) self.options.indent else 1;

        var i: usize = 0;
        while (i < self.current_indent * indent_size) : (i += 1) {
            try self.output.append(self.allocator, indent_char);
        }
    }
};

/// Convenience function to stringify a table with default options
pub fn stringify(allocator: std.mem.Allocator, table: *const Table) ![]const u8 {
    var stringifier = Stringifier.init(allocator, .{});
    defer stringifier.deinit();

    const result = try stringifier.stringify(table);
    return try allocator.dupe(u8, result);
}

/// Stringify with custom formatting options
pub fn stringifyWithOptions(allocator: std.mem.Allocator, table: *const Table, options: FormatOptions) ![]const u8 {
    var stringifier = Stringifier.init(allocator, options);
    defer stringifier.deinit();

    const result = try stringifier.stringify(table);
    return try allocator.dupe(u8, result);
}

test "stringify simple values" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\name = "zontom"
        \\version = 1
        \\enabled = true
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const result = try stringify(testing.allocator, &table);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "name = \"zontom\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "version = 1") != null);
    try testing.expect(std.mem.indexOf(u8, result, "enabled = true") != null);
}

test "stringify with table" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\[package]
        \\name = "test"
        \\version = "1.0"
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const result = try stringify(testing.allocator, &table);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "[package]") != null);
    try testing.expect(std.mem.indexOf(u8, result, "name = \"test\"") != null);
}

test "stringify with array" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source = "numbers = [1, 2, 3]";

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const result = try stringify(testing.allocator, &table);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "numbers = [1, 2, 3]") != null);
}

test "stringify with nested arrays" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source = "matrix = [[1, 2], [3, 4]]";

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const result = try stringify(testing.allocator, &table);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "matrix = [[1, 2], [3, 4]]") != null);
}

test "stringify with array of tables" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\[[users]]
        \\name = "Alice"
        \\admin = true
        \\
        \\[[users]]
        \\name = "Bob"
        \\admin = false
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const result = try stringify(testing.allocator, &table);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "[[users]]") != null);
    try testing.expect(std.mem.indexOf(u8, result, "name = \"Alice\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "name = \"Bob\"") != null);
}

test "stringify with special characters in strings" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\text = "Hello\nWorld\t!"
        \\quote = "Say \"hi\""
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const result = try stringify(testing.allocator, &table);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "\\n") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\\t") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\\\"") != null);
}

test "stringify with boolean and float values" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\enabled = true
        \\disabled = false
        \\pi = 3.14159
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const result = try stringify(testing.allocator, &table);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "enabled = true") != null);
    try testing.expect(std.mem.indexOf(u8, result, "disabled = false") != null);
    try testing.expect(std.mem.indexOf(u8, result, "pi = 3.14159") != null);
}

test "stringify with nested tables" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\[server]
        \\host = "localhost"
        \\
        \\[server.ssl]
        \\enabled = true
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const result = try stringify(testing.allocator, &table);
    defer testing.allocator.free(result);

    try testing.expect(std.mem.indexOf(u8, result, "[server]") != null);
    try testing.expect(std.mem.indexOf(u8, result, "[server.ssl]") != null);
    try testing.expect(std.mem.indexOf(u8, result, "host = \"localhost\"") != null);
    try testing.expect(std.mem.indexOf(u8, result, "enabled = true") != null);
}

test "stringify with format options - sorted keys" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\zebra = 1
        \\apple = 2
        \\monkey = 3
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const result = try stringifyWithOptions(testing.allocator, &table, .{ .sort_keys = true });
    defer testing.allocator.free(result);

    // Check that "apple" comes before "monkey" which comes before "zebra"
    const apple_pos = std.mem.indexOf(u8, result, "apple").?;
    const monkey_pos = std.mem.indexOf(u8, result, "monkey").?;
    const zebra_pos = std.mem.indexOf(u8, result, "zebra").?;

    try testing.expect(apple_pos < monkey_pos);
    try testing.expect(monkey_pos < zebra_pos);
}

test "round-trip: parse -> stringify -> parse" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\title = "Round Trip Test"
        \\count = 42
        \\enabled = true
        \\
        \\[database]
        \\host = "localhost"
        \\port = 5432
        \\
        \\[[users]]
        \\name = "Alice"
        \\
        \\[[users]]
        \\name = "Bob"
    ;

    // First parse
    var table1 = try zontom.parse(testing.allocator, source);
    defer table1.deinit();

    // Stringify
    const stringified = try stringify(testing.allocator, &table1);
    defer testing.allocator.free(stringified);

    // Second parse
    var table2 = try zontom.parse(testing.allocator, stringified);
    defer table2.deinit();

    // Verify values match
    try testing.expectEqualStrings("Round Trip Test", zontom.getString(&table2, "title").?);
    try testing.expectEqual(@as(i64, 42), zontom.getInt(&table2, "count").?);
    try testing.expectEqual(true, zontom.getBool(&table2, "enabled").?);

    const db = zontom.getTable(&table2, "database").?;
    try testing.expectEqualStrings("localhost", zontom.getString(db, "host").?);
    try testing.expectEqual(@as(i64, 5432), zontom.getInt(db, "port").?);

    const users = zontom.getArray(&table2, "users").?;
    try testing.expectEqual(@as(usize, 2), users.items.items.len);
}
