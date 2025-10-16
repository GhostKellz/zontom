//! Auto-generate schemas from Zig types
//!
//! Automatically create schema definitions from struct types

const std = @import("std");
const schema_mod = @import("schema.zig");

const Schema = schema_mod.Schema;
const FieldSchema = schema_mod.FieldSchema;
const ValueType = schema_mod.ValueType;
const SchemaBuilder = schema_mod.SchemaBuilder;

/// Generate a schema from a Zig struct type
pub fn schemaFrom(comptime T: type, allocator: std.mem.Allocator) !Schema {
    const type_info = @typeInfo(T);

    switch (type_info) {
        .Struct => |struct_info| {
            var builder = SchemaBuilder.init(allocator);
            defer builder.deinit();

            inline for (struct_info.fields) |field| {
                const field_schema = try createFieldSchema(field);
                _ = try builder.addField(field_schema);
            }

            _ = builder.allowUnknown(false);
            return try builder.build();
        },
        else => @compileError("schemaFrom only works with struct types"),
    }
}

fn createFieldSchema(comptime field: std.builtin.Type.StructField) FieldSchema {
    return FieldSchema{
        .name = field.name,
        .field_type = inferValueType(field.type),
        .required = !hasDefault(field),
        .description = null,
    };
}

fn hasDefault(comptime field: std.builtin.Type.StructField) bool {
    return field.default_value != null;
}

fn inferValueType(comptime T: type) ValueType {
    const type_info = @typeInfo(T);

    return switch (type_info) {
        .Int => .integer,
        .Float => .float,
        .Bool => .boolean,
        .Pointer => |ptr_info| {
            if (ptr_info.size == .Slice and ptr_info.child == u8) {
                return .string;
            }
            return .array;
        },
        .Optional => |opt_info| inferValueType(opt_info.child),
        .Struct => .table,
        .Array => .array,
        else => .any,
    };
}

test "generate schema from struct" {
    const testing = std.testing;

    const Config = struct {
        name: []const u8,
        port: i64,
        debug: bool = false,
    };

    const schema_val = try schemaFrom(Config, testing.allocator);
    defer testing.allocator.free(schema_val.fields);

    try testing.expectEqual(@as(usize, 3), schema_val.fields.len);
    try testing.expectEqualStrings("name", schema_val.fields[0].name);
    try testing.expectEqual(ValueType.string, schema_val.fields[0].field_type);
    try testing.expectEqual(true, schema_val.fields[0].required);

    try testing.expectEqualStrings("port", schema_val.fields[1].name);
    try testing.expectEqual(ValueType.integer, schema_val.fields[1].field_type);
    try testing.expectEqual(true, schema_val.fields[1].required);

    try testing.expectEqualStrings("debug", schema_val.fields[2].name);
    try testing.expectEqual(ValueType.boolean, schema_val.fields[2].field_type);
    try testing.expectEqual(false, schema_val.fields[2].required);
}

test "schema validation with generated schema" {
    const testing = std.testing;
    const zontom = @import("root.zig");

    const ServerConfig = struct {
        host: []const u8,
        port: i64,
        workers: i64 = 4,
    };

    const schema_val = try schemaFrom(ServerConfig, testing.allocator);
    defer testing.allocator.free(schema_val.fields);

    const valid_toml =
        \\host = "localhost"
        \\port = 8080
    ;

    var table = try zontom.parse(testing.allocator, valid_toml);
    defer table.deinit();

    var result = schema_val.validate(&table);
    defer result.deinit();

    try testing.expect(result.valid);
}

test "schema generation with optional fields" {
    const testing = std.testing;

    const Config = struct {
        name: []const u8,
        description: ?[]const u8 = null,
        port: ?i64 = null,
    };

    const schema_val = try schemaFrom(Config, testing.allocator);
    defer testing.allocator.free(schema_val.fields);

    try testing.expectEqual(@as(usize, 3), schema_val.fields.len);
    try testing.expectEqual(true, schema_val.fields[0].required);  // name
    try testing.expectEqual(false, schema_val.fields[1].required); // description (has default)
    try testing.expectEqual(false, schema_val.fields[2].required); // port (has default)
}
