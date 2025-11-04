//! Convert TOML to/from other formats (JSON, YAML, etc.)

const std = @import("std");
const value_mod = @import("value.zig");
const Io = std.Io;

const Value = value_mod.Value;
const Table = value_mod.Table;
const Array = value_mod.Array;

pub const ConvertError = error{
    OutOfMemory,
    InvalidValue,
};

/// Convert a TOML table to JSON string
pub fn toJSON(allocator: std.mem.Allocator, table: *const Table) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    try writeTableAsJSON(&output, table);
    return try output.toOwnedSlice();
}

fn writeTableAsJSON(output: *std.ArrayList(u8), table: *const Table) !void {
    try output.append('{');

    var first = true;
    var it = table.map.iterator();
    while (it.next()) |entry| {
        if (!first) try output.appendSlice(", ");
        first = false;

        // Write key
        try writeJSONString(output, entry.key_ptr.*);
        try output.appendSlice(": ");

        // Write value
        try writeValueAsJSON(output, entry.value_ptr);
    }

    try output.append('}');
}

fn writeValueAsJSON(output: *std.ArrayList(u8), val: *const Value) !void {
    switch (val.*) {
        .string => |s| try writeJSONString(output, s),
        .integer => |i| try appendFmt(output, "{d}", .{i}),
        .float => |f| try appendFmt(output, "{d}", .{f}),
        .boolean => |b| try output.appendSlice(if (b) "true" else "false"),
        .datetime => |dt| {
            try output.append('"');
            try appendFmt(output, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
                dt.year,
                dt.month,
                dt.day,
                dt.hour,
                dt.minute,
                dt.second,
            });
            if (dt.offset_minutes) |offset| {
                const sign: u8 = if (offset < 0) '-' else '+';
                const abs_offset: u16 = @abs(offset);
                const hours = abs_offset / 60;
                const minutes = abs_offset % 60;
                try appendFmt(output, "{c}{d:0>2}:{d:0>2}", .{ sign, hours, minutes });
            } else {
                try output.append('Z');
            }
            try output.append('"');
        },
        .date => |d| {
            try output.append('"');
            try appendFmt(output, "{d:0>4}-{d:0>2}-{d:0>2}", .{ d.year, d.month, d.day });
            try output.append('"');
        },
        .time => |t| {
            try output.append('"');
            try appendFmt(output, "{d:0>2}:{d:0>2}:{d:0>2}", .{ t.hour, t.minute, t.second });
            try output.append('"');
        },
        .array => |*arr| try writeArrayAsJSON(output, arr),
        .table => |tbl| try writeTableAsJSON(output, tbl),
    }
}

fn writeArrayAsJSON(output: *std.ArrayList(u8), arr: *const Array) !void {
    try output.append('[');

    for (arr.items.items, 0..) |item, i| {
        if (i > 0) try output.appendSlice(", ");
        try writeValueAsJSON(output, &item);
    }

    try output.append(']');
}

fn writeJSONString(output: *std.ArrayList(u8), s: []const u8) !void {
    try output.append('"');
    for (s) |c| {
        switch (c) {
            '"' => try output.appendSlice("\\\""),
            '\\' => try output.appendSlice("\\\\"),
            '\n' => try output.appendSlice("\\n"),
            '\r' => try output.appendSlice("\\r"),
            '\t' => try output.appendSlice("\\t"),
            '\x08' => try output.appendSlice("\\b"),
            '\x0C' => try output.appendSlice("\\f"),
            else => if (c < 0x20) {
                try appendFmt(output, "\\u{x:0>4}", .{c});
            } else {
                try output.append(c);
            },
        }
    }
    try output.append('"');
}

/// Convert a TOML table to pretty-printed JSON
pub fn toJSONPretty(allocator: std.mem.Allocator, table: *const Table, indent: usize) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    try writeTableAsJSONPretty(&output, table, indent, 0);
    try output.append('\n');
    return try output.toOwnedSlice();
}

fn writeTableAsJSONPretty(output: *std.ArrayList(u8), table: *const Table, indent_size: usize, level: usize) !void {
    try output.appendSlice("{\n");

    var first = true;
    var it = table.map.iterator();
    while (it.next()) |entry| {
        if (!first) try output.appendSlice(",\n");
        first = false;

        // Indent
        try writeIndent(output, indent_size, level + 1);

        // Write key
        try writeJSONString(output, entry.key_ptr.*);
        try output.appendSlice(": ");

        // Write value
        try writeValueAsJSONPretty(output, entry.value_ptr, indent_size, level + 1);
    }

    try output.append('\n');
    try writeIndent(output, indent_size, level);
    try output.append('}');
}

fn writeValueAsJSONPretty(output: *std.ArrayList(u8), val: *const Value, indent_size: usize, level: usize) !void {
    switch (val.*) {
        .string => |s| try writeJSONString(output, s),
        .integer => |i| try appendFmt(output, "{d}", .{i}),
        .float => |f| try appendFmt(output, "{d}", .{f}),
        .boolean => |b| try output.appendSlice(if (b) "true" else "false"),
        .datetime => |dt| {
            try output.append('"');
            try appendFmt(output, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
                dt.year,
                dt.month,
                dt.day,
                dt.hour,
                dt.minute,
                dt.second,
            });
            if (dt.offset_minutes) |offset| {
                const sign: u8 = if (offset < 0) '-' else '+';
                const abs_offset: u16 = @abs(offset);
                const hours = abs_offset / 60;
                const minutes = abs_offset % 60;
                try appendFmt(output, "{c}{d:0>2}:{d:0>2}", .{ sign, hours, minutes });
            } else {
                try output.append('Z');
            }
            try output.append('"');
        },
        .date => |d| {
            try output.append('"');
            try appendFmt(output, "{d:0>4}-{d:0>2}-{d:0>2}", .{ d.year, d.month, d.day });
            try output.append('"');
        },
        .time => |t| {
            try output.append('"');
            try appendFmt(output, "{d:0>2}:{d:0>2}:{d:0>2}", .{ t.hour, t.minute, t.second });
            try output.append('"');
        },
        .array => |*arr| try writeArrayAsJSONPretty(output, arr, indent_size, level),
        .table => |tbl| try writeTableAsJSONPretty(output, tbl, indent_size, level),
    }
}

fn writeArrayAsJSONPretty(output: *std.ArrayList(u8), arr: *const Array, indent_size: usize, level: usize) !void {
    if (arr.items.items.len == 0) {
        try output.appendSlice("[]");
        return;
    }

    // Check if all items are simple (not tables/arrays)
    var all_simple = true;
    for (arr.items.items) |item| {
        if (item == .table or item == .array) {
            all_simple = false;
            break;
        }
    }

    if (all_simple and arr.items.items.len <= 5) {
        // Inline simple arrays
        try output.append('[');
        for (arr.items.items, 0..) |item, i| {
            if (i > 0) try output.appendSlice(", ");
            try writeValueAsJSONPretty(output, &item, indent_size, level);
        }
        try output.append(']');
    } else {
        // Multi-line arrays
        try output.appendSlice("[\n");
        for (arr.items.items, 0..) |item, i| {
            if (i > 0) try output.appendSlice(",\n");
            try writeIndent(output, indent_size, level + 1);
            try writeValueAsJSONPretty(output, &item, indent_size, level + 1);
        }
        try output.append('\n');
        try writeIndent(output, indent_size, level);
        try output.append(']');
    }
}

fn appendFmt(output: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) ConvertError!void {
    var writer = Io.Writer.Allocating.fromArrayList(output.allocator, output);
    defer output.* = Io.Writer.Allocating.toArrayList(&writer);
    writer.writer.print(fmt, args) catch |err| {
        return switch (err) {
            error.WriteFailed => error.InvalidValue,
        };
    };
}

fn writeIndent(output: *std.ArrayList(u8), indent_size: usize, level: usize) !void {
    var i: usize = 0;
    while (i < level * indent_size) : (i += 1) {
        try output.append(' ');
    }
}

test "convert to JSON" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\name = "test"
        \\port = 8080
        \\enabled = true
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const json = try toJSON(testing.allocator, &table);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"name\": \"test\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"port\": 8080") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"enabled\": true") != null);
}

test "convert nested structure to JSON" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\[server]
        \\host = "localhost"
        \\port = 8080
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const json = try toJSON(testing.allocator, &table);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"server\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"host\": \"localhost\"") != null);
}

test "convert array to JSON" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source = "numbers = [1, 2, 3]";

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const json = try toJSON(testing.allocator, &table);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "\"numbers\": [1, 2, 3]") != null);
}

test "convert to pretty JSON" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\name = "test"
        \\port = 8080
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const json = try toJSONPretty(testing.allocator, &table, 2);
    defer testing.allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "{\n") != null);
    try testing.expect(std.mem.indexOf(u8, json, "  \"name\"") != null);
}
