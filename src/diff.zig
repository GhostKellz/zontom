//! TOML diff and merge utilities

const std = @import("std");
const value_mod = @import("value.zig");

const Value = value_mod.Value;
const Table = value_mod.Table;

pub const DiffType = enum {
    added,
    removed,
    modified,
};

pub const Diff = struct {
    path: []const u8,
    diff_type: DiffType,
    old_value: ?Value,
    new_value: ?Value,
};

pub const DiffResult = struct {
    allocator: std.mem.Allocator,
    diffs: std.ArrayList(Diff),

    pub fn init(allocator: std.mem.Allocator) DiffResult {
        return .{
            .allocator = allocator,
            .diffs = std.ArrayList(Diff).init(allocator),
        };
    }

    pub fn deinit(self: *DiffResult) void {
        for (self.diffs.items) |item| {
            self.allocator.free(item.path);
        }
        self.diffs.deinit();
    }
};

/// Compare two TOML tables and return differences
pub fn diff(allocator: std.mem.Allocator, old: *const Table, new: *const Table) !DiffResult {
    var result = DiffResult.init(allocator);
    try diffTables(allocator, &result, old, new, "");
    return result;
}

fn diffTables(
    allocator: std.mem.Allocator,
    result: *DiffResult,
    old: *const Table,
    new: *const Table,
    prefix: []const u8,
) !void {
    // Check for removed and modified keys
    var old_it = old.map.iterator();
    while (old_it.next()) |old_entry| {
        const key = old_entry.key_ptr.*;
        const old_val = old_entry.value_ptr;

        const path = if (prefix.len > 0)
            try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, key })
        else
            try allocator.dupe(u8, key);

        if (new.get(key)) |new_val| {
            // Key exists in both - check if modified
            if (!valuesEqual(old_val, &new_val)) {
                if (old_val.* == .table and new_val == .table) {
                    // Recursively diff nested tables
                    try diffTables(allocator, result, old_val.table, new_val.table, path);
                    allocator.free(path);
                } else {
                    try result.diffs.append(.{
                        .path = path,
                        .diff_type = .modified,
                        .old_value = old_val.*,
                        .new_value = new_val,
                    });
                }
            } else {
                allocator.free(path);
            }
        } else {
            // Key removed
            try result.diffs.append(.{
                .path = path,
                .diff_type = .removed,
                .old_value = old_val.*,
                .new_value = null,
            });
        }
    }

    // Check for added keys
    var new_it = new.map.iterator();
    while (new_it.next()) |new_entry| {
        const key = new_entry.key_ptr.*;
        const new_val = new_entry.value_ptr;

        if (old.get(key) == null) {
            const path = if (prefix.len > 0)
                try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, key })
            else
                try allocator.dupe(u8, key);

            try result.diffs.append(.{
                .path = path,
                .diff_type = .added,
                .old_value = null,
                .new_value = new_val.*,
            });
        }
    }
}

fn valuesEqual(a: *const Value, b: *const Value) bool {
    if (@intFromEnum(a.*) != @intFromEnum(b.*)) return false;

    return switch (a.*) {
        .string => |s| std.mem.eql(u8, s, b.string),
        .integer => |i| i == b.integer,
        .float => |f| f == b.float,
        .boolean => |bo| bo == b.boolean,
        .datetime => |dt| std.meta.eql(dt, b.datetime),
        .date => |d| std.meta.eql(d, b.date),
        .time => |t| std.meta.eql(t, b.time),
        .array => false, // Simplified - could do deep comparison
        .table => false, // Simplified - tables compared recursively above
    };
}

/// Merge two TOML tables (new overwrites old)
pub fn merge(allocator: std.mem.Allocator, base: *const Table, overlay: *const Table) !Table {
    var result = Table.init(allocator);
    errdefer result.deinit();

    // Copy all from base
    var base_it = base.map.iterator();
    while (base_it.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        try result.put(key, try cloneValue(allocator, entry.value_ptr));
    }

    // Merge overlay
    var overlay_it = overlay.map.iterator();
    while (overlay_it.next()) |entry| {
        const key = entry.key_ptr.*;

        if (result.getPtr(key)) |existing| {
            // Key exists - merge if both are tables
            if (existing.* == .table and entry.value_ptr.* == .table) {
                const merged = try merge(allocator, existing.table, entry.value_ptr.table);
                existing.*.deinit(allocator);
                existing.* = Value{ .table = &merged };
            } else {
                // Otherwise replace
                existing.*.deinit(allocator);
                existing.* = try cloneValue(allocator, entry.value_ptr);
            }
        } else {
            // New key
            const key_copy = try allocator.dupe(u8, key);
            try result.put(key_copy, try cloneValue(allocator, entry.value_ptr));
        }
    }

    return result;
}

fn cloneValue(allocator: std.mem.Allocator, val: *const Value) !Value {
    return switch (val.*) {
        .string => |s| Value{ .string = try allocator.dupe(u8, s) },
        .integer => |i| Value{ .integer = i },
        .float => |f| Value{ .float = f },
        .boolean => |b| Value{ .boolean = b },
        .datetime => |dt| Value{ .datetime = dt },
        .date => |d| Value{ .date = d },
        .time => |t| Value{ .time = t },
        .array => |*arr| {
            var new_arr = value_mod.Array.init(allocator);
            for (arr.items.items) |item| {
                try new_arr.items.append(allocator, try cloneValue(allocator, &item));
            }
            return Value{ .array = new_arr };
        },
        .table => |tbl| {
            var new_tbl = Table.init(allocator);
            var it = tbl.map.iterator();
            while (it.next()) |entry| {
                const key = try allocator.dupe(u8, entry.key_ptr.*);
                try new_tbl.put(key, try cloneValue(allocator, entry.value_ptr));
            }
            const boxed = try allocator.create(Table);
            boxed.* = new_tbl;
            return Value{ .table = boxed };
        },
    };
}

test "diff: detect added fields" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const old_toml = "name = \"test\"";
    const new_toml =
        \\name = "test"
        \\version = "1.0"
    ;

    var old_table = try zontom.parse(testing.allocator, old_toml);
    defer old_table.deinit();

    var new_table = try zontom.parse(testing.allocator, new_toml);
    defer new_table.deinit();

    var result = try diff(testing.allocator, &old_table, &new_table);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.diffs.items.len);
    try testing.expectEqual(DiffType.added, result.diffs.items[0].diff_type);
}

test "diff: detect removed fields" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const old_toml =
        \\name = "test"
        \\version = "1.0"
    ;
    const new_toml = "name = \"test\"";

    var old_table = try zontom.parse(testing.allocator, old_toml);
    defer old_table.deinit();

    var new_table = try zontom.parse(testing.allocator, new_toml);
    defer new_table.deinit();

    var result = try diff(testing.allocator, &old_table, &new_table);
    defer result.deinit();

    try testing.expectEqual(@as(usize, 1), result.diffs.items.len);
    try testing.expectEqual(DiffType.removed, result.diffs.items[0].diff_type);
}

test "merge: simple merge" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const base_toml =
        \\name = "base"
        \\version = "1.0"
    ;
    const overlay_toml = "name = \"overlay\"";

    var base = try zontom.parse(testing.allocator, base_toml);
    defer base.deinit();

    var overlay = try zontom.parse(testing.allocator, overlay_toml);
    defer overlay.deinit();

    var merged = try merge(testing.allocator, &base, &overlay);
    defer merged.deinit();

    const name = zontom.getString(&merged, "name").?;
    try testing.expectEqualStrings("overlay", name);

    const version = zontom.getString(&merged, "version").?;
    try testing.expectEqualStrings("1.0", version);
}
