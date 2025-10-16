//! Schema validation for TOML tables
//!
//! Allows defining schemas to validate TOML structure and types

const std = @import("std");
const value = @import("value.zig");

const Value = value.Value;
const Table = value.Table;
const Array = value.Array;

pub const ValidationError = error{
    MissingRequiredField,
    InvalidType,
    InvalidValue,
    UnknownField,
    OutOfMemory,
};

pub const ValidationResult = struct {
    valid: bool,
    errors: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) ValidationResult {
        return .{
            .valid = true,
            .errors = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ValidationResult) void {
        for (self.errors.items) |err| {
            self.errors.allocator.free(err);
        }
        self.errors.deinit();
    }

    pub fn addError(self: *ValidationResult, message: []const u8) !void {
        const owned = try self.errors.allocator.dupe(u8, message);
        try self.errors.append(owned);
        self.valid = false;
    }
};

pub const ValueType = enum {
    string,
    integer,
    float,
    boolean,
    datetime,
    date,
    time,
    array,
    table,
    any,
};

pub const Constraint = union(enum) {
    min_value: i64,
    max_value: i64,
    min_length: usize,
    max_length: usize,
    pattern: []const u8,
    one_of: []const []const u8,
    custom: *const fn (value: *const Value) bool,
};

pub const FieldSchema = struct {
    name: []const u8,
    field_type: ValueType,
    required: bool = false,
    default_value: ?Value = null,
    constraints: []const Constraint = &.{},
    description: ?[]const u8 = null,
    nested_schema: ?*const Schema = null,
};

pub const Schema = struct {
    fields: []const FieldSchema,
    allow_unknown: bool = false,
    description: ?[]const u8 = null,

    pub fn validate(self: *const Schema, table: *const Table) ValidationResult {
        var result = ValidationResult.init(table.allocator);

        // Check required fields
        for (self.fields) |field| {
            const val = table.get(field.name);

            if (val == null) {
                if (field.required) {
                    const msg = std.fmt.allocPrint(
                        table.allocator,
                        "Missing required field: '{s}'",
                        .{field.name},
                    ) catch continue;
                    result.addError(msg) catch {};
                }
                continue;
            }

            // Type validation
            self.validateType(field, val.?, &result) catch {};

            // Constraint validation
            self.validateConstraints(field, val.?, &result) catch {};

            // Nested schema validation
            if (field.nested_schema) |nested| {
                if (val.? == .table) {
                    var nested_result = nested.validate(val.?.table);
                    defer nested_result.deinit();

                    if (!nested_result.valid) {
                        for (nested_result.errors.items) |err| {
                            const prefixed = std.fmt.allocPrint(
                                table.allocator,
                                "{s}.{s}",
                                .{ field.name, err },
                            ) catch continue;
                            result.addError(prefixed) catch {};
                        }
                    }
                }
            }
        }

        // Check for unknown fields if strict mode
        if (!self.allow_unknown) {
            var it = table.map.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                var found = false;

                for (self.fields) |field| {
                    if (std.mem.eql(u8, field.name, key)) {
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    const msg = std.fmt.allocPrint(
                        table.allocator,
                        "Unknown field: '{s}'",
                        .{key},
                    ) catch continue;
                    result.addError(msg) catch {};
                }
            }
        }

        return result;
    }

    fn validateType(self: *const Schema, field: FieldSchema, val: Value, result: *ValidationResult) !void {
        _ = self;

        const matches = switch (field.field_type) {
            .string => val == .string,
            .integer => val == .integer,
            .float => val == .float,
            .boolean => val == .boolean,
            .datetime => val == .datetime,
            .date => val == .date,
            .time => val == .time,
            .array => val == .array,
            .table => val == .table,
            .any => true,
        };

        if (!matches) {
            const msg = try std.fmt.allocPrint(
                result.errors.allocator,
                "Field '{s}' has wrong type (expected {s})",
                .{ field.name, @tagName(field.field_type) },
            );
            try result.addError(msg);
        }
    }

    fn validateConstraints(self: *const Schema, field: FieldSchema, val: Value, result: *ValidationResult) !void {
        _ = self;

        for (field.constraints) |constraint| {
            switch (constraint) {
                .min_value => |min| {
                    if (val == .integer and val.integer < min) {
                        const msg = try std.fmt.allocPrint(
                            result.errors.allocator,
                            "Field '{s}' value {d} is less than minimum {d}",
                            .{ field.name, val.integer, min },
                        );
                        try result.addError(msg);
                    }
                },
                .max_value => |max| {
                    if (val == .integer and val.integer > max) {
                        const msg = try std.fmt.allocPrint(
                            result.errors.allocator,
                            "Field '{s}' value {d} is greater than maximum {d}",
                            .{ field.name, val.integer, max },
                        );
                        try result.addError(msg);
                    }
                },
                .min_length => |min| {
                    if (val == .string and val.string.len < min) {
                        const msg = try std.fmt.allocPrint(
                            result.errors.allocator,
                            "Field '{s}' length {d} is less than minimum {d}",
                            .{ field.name, val.string.len, min },
                        );
                        try result.addError(msg);
                    }
                },
                .max_length => |max| {
                    if (val == .string and val.string.len > max) {
                        const msg = try std.fmt.allocPrint(
                            result.errors.allocator,
                            "Field '{s}' length {d} is greater than maximum {d}",
                            .{ field.name, val.string.len, max },
                        );
                        try result.addError(msg);
                    }
                },
                .pattern => |_| {
                    // Pattern matching would require regex library
                    // Skip for now
                },
                .one_of => |options| {
                    if (val == .string) {
                        var found = false;
                        for (options) |opt| {
                            if (std.mem.eql(u8, val.string, opt)) {
                                found = true;
                                break;
                            }
                        }
                        if (!found) {
                            const msg = try std.fmt.allocPrint(
                                result.errors.allocator,
                                "Field '{s}' value '{s}' is not one of the allowed values",
                                .{ field.name, val.string },
                            );
                            try result.addError(msg);
                        }
                    }
                },
                .custom => |func| {
                    if (!func(&val)) {
                        const msg = try std.fmt.allocPrint(
                            result.errors.allocator,
                            "Field '{s}' failed custom validation",
                            .{field.name},
                        );
                        try result.addError(msg);
                    }
                },
            }
        }
    }
};

/// Builder pattern for creating schemas
pub const SchemaBuilder = struct {
    allocator: std.mem.Allocator,
    fields: std.ArrayList(FieldSchema),
    allow_unknown: bool,
    description: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator) SchemaBuilder {
        return .{
            .allocator = allocator,
            .fields = std.ArrayList(FieldSchema).init(allocator),
            .allow_unknown = false,
            .description = null,
        };
    }

    pub fn deinit(self: *SchemaBuilder) void {
        self.fields.deinit();
    }

    pub fn allowUnknown(self: *SchemaBuilder, allow: bool) *SchemaBuilder {
        self.allow_unknown = allow;
        return self;
    }

    pub fn setDescription(self: *SchemaBuilder, desc: []const u8) *SchemaBuilder {
        self.description = desc;
        return self;
    }

    pub fn addField(self: *SchemaBuilder, field: FieldSchema) !*SchemaBuilder {
        try self.fields.append(field);
        return self;
    }

    pub fn build(self: *SchemaBuilder) !Schema {
        const fields_slice = try self.allocator.dupe(FieldSchema, self.fields.items);
        return Schema{
            .fields = fields_slice,
            .allow_unknown = self.allow_unknown,
            .description = self.description,
        };
    }
};

test "schema validation - required fields" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source = "name = \"test\"";

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const schema = Schema{
        .fields = &[_]FieldSchema{
            .{ .name = "name", .field_type = .string, .required = true },
            .{ .name = "version", .field_type = .string, .required = true },
        },
    };

    var result = schema.validate(&table);
    defer result.deinit();

    try testing.expect(!result.valid);
    try testing.expect(result.errors.items.len > 0);
}

test "schema validation - type checking" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source = "port = \"8080\""; // String instead of integer

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const schema = Schema{
        .fields = &[_]FieldSchema{
            .{ .name = "port", .field_type = .integer, .required = true },
        },
    };

    var result = schema.validate(&table);
    defer result.deinit();

    try testing.expect(!result.valid);
}

test "schema validation - constraints" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source = "port = 99999"; // Too high

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const schema = Schema{
        .fields = &[_]FieldSchema{
            .{
                .name = "port",
                .field_type = .integer,
                .required = true,
                .constraints = &[_]Constraint{
                    .{ .min_value = 1 },
                    .{ .max_value = 65535 },
                },
            },
        },
    };

    var result = schema.validate(&table);
    defer result.deinit();

    try testing.expect(!result.valid);
}

test "schema validation - success case" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\name = "myapp"
        \\port = 8080
        \\debug = true
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const schema = Schema{
        .fields = &[_]FieldSchema{
            .{ .name = "name", .field_type = .string, .required = true },
            .{ .name = "port", .field_type = .integer, .required = true },
            .{ .name = "debug", .field_type = .boolean, .required = false },
        },
    };

    var result = schema.validate(&table);
    defer result.deinit();

    try testing.expect(result.valid);
    try testing.expectEqual(@as(usize, 0), result.errors.items.len);
}

test "schema validation - unknown fields" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\name = "test"
        \\unknown_field = "value"
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const schema = Schema{
        .fields = &[_]FieldSchema{
            .{ .name = "name", .field_type = .string, .required = true },
        },
        .allow_unknown = false,
    };

    var result = schema.validate(&table);
    defer result.deinit();

    try testing.expect(!result.valid);
}

test "schema validation - allow unknown fields" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const source =
        \\name = "test"
        \\unknown_field = "value"
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const schema = Schema{
        .fields = &[_]FieldSchema{
            .{ .name = "name", .field_type = .string, .required = true },
        },
        .allow_unknown = true,
    };

    var result = schema.validate(&table);
    defer result.deinit();

    try testing.expect(result.valid);
}

test "schema builder pattern" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    var builder = SchemaBuilder.init(testing.allocator);
    defer builder.deinit();

    _ = try builder
        .addField(.{ .name = "name", .field_type = .string, .required = true })
        .addField(.{ .name = "port", .field_type = .integer, .required = true })
        .allowUnknown(true);

    const schema = try builder.build();
    defer testing.allocator.free(schema.fields);

    const source =
        \\name = "test"
        \\port = 8080
    ;

    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    var result = schema.validate(&table);
    defer result.deinit();

    try testing.expect(result.valid);
}
