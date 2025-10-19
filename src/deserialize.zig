//! Comptime struct deserialization from TOML
//!
//! Automatically convert TOML tables into Zig structs

const std = @import("std");
const value = @import("value.zig");
const root = @import("root.zig");

const Value = value.Value;
const Table = value.Table;
const Array = value.Array;

pub const DeserializeError = error{
    MissingField,
    TypeMismatch,
    InvalidValue,
    OutOfMemory,
};

/// Parse TOML source directly into a Zig struct
pub fn parseInto(comptime T: type, allocator: std.mem.Allocator, source: []const u8) !T {
    var table = try root.parse(allocator, source);
    defer table.deinit();

    return try deserialize(T, allocator, &table);
}

/// Deserialize a TOML table into a Zig struct
pub fn deserialize(comptime T: type, allocator: std.mem.Allocator, table: *const Table) !T {
    const type_info = @typeInfo(T);

    switch (type_info) {
        .@"struct" => |struct_info| {
            var result: T = undefined;

            inline for (struct_info.fields) |field| {
                const val = table.get(field.name);

                if (val == null) {
                    // In Zig 0.16, we can't check for default values at comptime reliably
                    // So we require a default value to be set on the struct definition
                    // If you get MissingField error, add a default value to your struct field
                    return error.MissingField;
                }

                @field(result, field.name) = try deserializeValue(field.type, allocator, val.?);
            }

            return result;
        },
        else => @compileError("deserialize only works with structs"),
    }
}

fn deserializeValue(comptime T: type, allocator: std.mem.Allocator, val: Value) !T {
    const type_info = @typeInfo(T);

    switch (type_info) {
        .int => {
            if (val != .integer) return error.TypeMismatch;
            return @intCast(val.integer);
        },
        .float => {
            if (val == .float) return @floatCast(val.float);
            if (val == .integer) return @floatFromInt(val.integer);
            return error.TypeMismatch;
        },
        .bool => {
            if (val != .boolean) return error.TypeMismatch;
            return val.boolean;
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .slice => {
                    if (ptr_info.child == u8) {
                        // String
                        if (val != .string) return error.TypeMismatch;
                        return try allocator.dupe(u8, val.string);
                    } else {
                        // Array slice
                        if (val != .array) return error.TypeMismatch;
                        const arr = val.array;
                        var result = try allocator.alloc(ptr_info.child, arr.items.items.len);
                        for (arr.items.items, 0..) |item, i| {
                            result[i] = try deserializeValue(ptr_info.child, allocator, item);
                        }
                        return result;
                    }
                },
                else => @compileError("Only slices are supported"),
            }
        },
        .optional => |opt_info| {
            return try deserializeValue(opt_info.child, allocator, val);
        },
        .@"struct" => {
            if (val != .table) return error.TypeMismatch;
            return try deserialize(T, allocator, val.table);
        },
        .array => |arr_info| {
            if (val != .array) return error.TypeMismatch;
            const arr = val.array;
            if (arr.items.items.len != arr_info.len) return error.InvalidValue;

            var result: T = undefined;
            for (arr.items.items, 0..) |item, i| {
                result[i] = try deserializeValue(arr_info.child, allocator, item);
            }
            return result;
        },
        else => @compileError("Unsupported type: " ++ @typeName(T)),
    }
}

/// Free memory allocated during deserialization
pub fn free(comptime T: type, allocator: std.mem.Allocator, data: T) void {
    const type_info = @typeInfo(T);

    switch (type_info) {
        .@"struct" => |struct_info| {
            inline for (struct_info.fields) |field| {
                freeValue(field.type, allocator, @field(data, field.name));
            }
        },
        else => {},
    }
}

fn freeValue(comptime T: type, allocator: std.mem.Allocator, val: T) void {
    const type_info = @typeInfo(T);

    switch (type_info) {
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .slice => {
                    if (ptr_info.child == u8) {
                        allocator.free(val);
                    } else {
                        for (val) |item| {
                            freeValue(ptr_info.child, allocator, item);
                        }
                        allocator.free(val);
                    }
                },
                else => {},
            }
        },
        .optional => |opt_info| {
            if (val) |v| {
                freeValue(opt_info.child, allocator, v);
            }
        },
        .@"struct" => {
            free(T, allocator, val);
        },
        else => {},
    }
}

test "deserialize simple struct" {
    const testing = std.testing;

    const Config = struct {
        name: []const u8,
        port: i64,
        debug: bool,
    };

    const source =
        \\name = "myapp"
        \\port = 8080
        \\debug = true
    ;

    const config = try parseInto(Config, testing.allocator, source);
    defer free(Config, testing.allocator, config);

    try testing.expectEqualStrings("myapp", config.name);
    try testing.expectEqual(@as(i64, 8080), config.port);
    try testing.expectEqual(true, config.debug);
}

test "deserialize with defaults" {
    const testing = std.testing;

    const Config = struct {
        name: []const u8,
        port: i64 = 3000,
        debug: bool = false,
    };

    const source = "name = \"test\"";

    const config = try parseInto(Config, testing.allocator, source);
    defer free(Config, testing.allocator, config);

    try testing.expectEqualStrings("test", config.name);
    try testing.expectEqual(@as(i64, 3000), config.port);
    try testing.expectEqual(false, config.debug);
}

test "deserialize nested struct" {
    const testing = std.testing;

    const Database = struct {
        host: []const u8,
        port: i64,
    };

    const Config = struct {
        name: []const u8,
        database: Database,
    };

    const source =
        \\name = "app"
        \\
        \\[database]
        \\host = "localhost"
        \\port = 5432
    ;

    const config = try parseInto(Config, testing.allocator, source);
    defer free(Config, testing.allocator, config);

    try testing.expectEqualStrings("app", config.name);
    try testing.expectEqualStrings("localhost", config.database.host);
    try testing.expectEqual(@as(i64, 5432), config.database.port);
}

test "deserialize with slices" {
    const testing = std.testing;

    const Config = struct {
        hosts: [][]const u8,
        ports: []i64,
    };

    const source =
        \\hosts = ["host1", "host2", "host3"]
        \\ports = [8080, 8081, 8082]
    ;

    const config = try parseInto(Config, testing.allocator, source);
    defer {
        for (config.hosts) |host| {
            testing.allocator.free(host);
        }
        testing.allocator.free(config.hosts);
        testing.allocator.free(config.ports);
    }

    try testing.expectEqual(@as(usize, 3), config.hosts.len);
    try testing.expectEqualStrings("host1", config.hosts[0]);
    try testing.expectEqual(@as(i64, 8080), config.ports[0]);
}

test "deserialize with optional fields" {
    const testing = std.testing;

    const Config = struct {
        name: []const u8,
        description: ?[]const u8 = null,
    };

    const source = "name = \"test\"";

    const config = try parseInto(Config, testing.allocator, source);
    defer free(Config, testing.allocator, config);

    try testing.expectEqualStrings("test", config.name);
    try testing.expectEqual(@as(?[]const u8, null), config.description);
}

test "deserialize float types" {
    const testing = std.testing;

    const Config = struct {
        temperature: f64,
        ratio: f32,
    };

    const source =
        \\temperature = 98.6
        \\ratio = 1.5
    ;

    const config = try parseInto(Config, testing.allocator, source);

    try testing.expectEqual(@as(f64, 98.6), config.temperature);
    try testing.expectEqual(@as(f32, 1.5), config.ratio);
}
