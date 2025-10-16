//! Core TOML value types and table structure
const std = @import("std");

/// TOML value type
pub const Value = union(enum) {
    string: []const u8,
    integer: i64,
    float: f64,
    boolean: bool,
    datetime: Datetime,
    date: Date,
    time: Time,
    array: Array,
    table: *Table,

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .string => |s| allocator.free(s),
            .array => |*arr| arr.deinit(allocator),
            .table => |tbl| {
                tbl.deinit();
                allocator.destroy(tbl);
            },
            else => {},
        }
    }
};

/// Array of TOML values
pub const Array = struct {
    items: std.ArrayList(Value),

    pub fn init(_: std.mem.Allocator) Array {
        return .{ .items = std.ArrayList(Value){} };
    }

    pub fn deinit(self: *Array, allocator: std.mem.Allocator) void {
        for (self.items.items) |*item| {
            item.deinit(allocator);
        }
        self.items.deinit(allocator);
    }
};

/// TOML table (string-keyed map)
pub const Table = struct {
    map: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Table {
        return .{
            .map = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Table) void {
        // First free all keys and deinit nested structures
        var it = self.map.iterator();
        while (it.next()) |entry| {
            // Free the key
            self.allocator.free(entry.key_ptr.*);
            // Deinit the value (including strings)
            var val = entry.value_ptr.*;
            val.deinit(self.allocator);
        }
        // Deinit the hash map structure
        self.map.deinit();
    }

    pub fn put(self: *Table, key: []const u8, value: Value) !void {
        // Duplicate the key
        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);
        try self.map.put(key_copy, value);
    }

    pub fn get(self: *const Table, key: []const u8) ?Value {
        return self.map.get(key);
    }

    pub fn getPtr(self: *Table, key: []const u8) ?*Value {
        return self.map.getPtr(key);
    }
};

/// RFC 3339 datetime
pub const Datetime = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    nanosecond: u32,
    offset_minutes: ?i16, // null = local time, 0 = UTC

    pub fn format(
        self: Datetime,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}", .{
            self.year,
            self.month,
            self.day,
            self.hour,
            self.minute,
            self.second,
        });
        if (self.nanosecond > 0) {
            try writer.print(".{d:0>9}", .{self.nanosecond});
        }
        if (self.offset_minutes) |offset| {
            if (offset == 0) {
                try writer.writeAll("Z");
            } else {
                const hours = @divTrunc(offset, 60);
                const mins = @rem(@abs(offset), 60);
                try writer.print("{c}{d:0>2}:{d:0>2}", .{
                    if (offset >= 0) '+' else '-',
                    @abs(hours),
                    mins,
                });
            }
        }
    }
};

/// Date (no time component)
pub const Date = struct {
    year: u16,
    month: u8,
    day: u8,

    pub fn format(
        self: Date,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{ self.year, self.month, self.day });
    }
};

/// Time (no date component)
pub const Time = struct {
    hour: u8,
    minute: u8,
    second: u8,
    nanosecond: u32,

    pub fn format(
        self: Time,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;
        try writer.print("{d:0>2}:{d:0>2}:{d:0>2}", .{ self.hour, self.minute, self.second });
        if (self.nanosecond > 0) {
            try writer.print(".{d:0>9}", .{self.nanosecond});
        }
    }
};

test "Table basic operations" {
    const testing = std.testing;

    var table = Table.init(testing.allocator);
    defer table.deinit();

    const name_str = try testing.allocator.dupe(u8, "zontom");
    try table.put("name", .{ .string = name_str });
    try table.put("version", .{ .integer = 1 });
    try table.put("enabled", .{ .boolean = true });

    const name = table.get("name");
    try testing.expect(name != null);
    try testing.expectEqualStrings("zontom", name.?.string);

    const version = table.get("version");
    try testing.expect(version != null);
    try testing.expectEqual(@as(i64, 1), version.?.integer);
}

test "Array operations" {
    const testing = std.testing;

    var arr = Array.init(testing.allocator);
    defer arr.deinit(testing.allocator);

    try arr.items.append(testing.allocator, .{ .integer = 1 });
    try arr.items.append(testing.allocator, .{ .integer = 2 });
    try arr.items.append(testing.allocator, .{ .integer = 3 });

    try testing.expectEqual(@as(usize, 3), arr.items.items.len);
    try testing.expectEqual(@as(i64, 2), arr.items.items[1].integer);
}
