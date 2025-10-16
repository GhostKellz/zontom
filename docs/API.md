# ZonTOM API Reference

Complete API documentation for ZonTOM v0.2.0

## Core Functions

### `parse()`

Parse TOML source string into a Table.

```zig
pub fn parse(allocator: std.mem.Allocator, source: []const u8) !Table
```

**Parameters:**
- `allocator`: Memory allocator for the table and its contents
- `source`: TOML source string to parse

**Returns:** `Table` on success, error on parse failure

**Example:**
```zig
var table = try zontom.parse(allocator, toml_source);
defer table.deinit();
```

### `parseWithContext()`

Parse with detailed error context for better error reporting.

```zig
pub fn parseWithContext(allocator: std.mem.Allocator, source: []const u8) ParseResult
```

**Parameters:**
- `allocator`: Memory allocator
- `source`: TOML source string

**Returns:** `ParseResult` containing either a `Table` or `ErrorContext`

**Example:**
```zig
var result = zontom.parseWithContext(allocator, source);
defer result.deinit();

if (result.error_context) |err| {
    // Handle error with context
    std.debug.print("Error at line {d}: {s}\\n", .{err.line, err.message});
    return;
}

var table = result.table.?;
```

## Getter Functions

### `getString()`

Get a string value from a table by key.

```zig
pub fn getString(table: *const Table, key: []const u8) ?[]const u8
```

**Parameters:**
- `table`: Table to search
- `key`: Key name

**Returns:** String value if found and is a string, `null` otherwise

**Example:**
```zig
if (zontom.getString(&table, "name")) |name| {
    std.debug.print("Name: {s}\\n", .{name});
}
```

### `getInt()`

Get an integer value from a table by key.

```zig
pub fn getInt(table: *const Table, key: []const u8) ?i64
```

**Returns:** `i64` value if found and is an integer, `null` otherwise

### `getFloat()`

Get a float value from a table by key.

```zig
pub fn getFloat(table: *const Table, key: []const u8) ?f64
```

**Returns:** `f64` value if found and is a float, `null` otherwise

### `getBool()`

Get a boolean value from a table by key.

```zig
pub fn getBool(table: *const Table, key: []const u8) ?bool
```

**Returns:** `bool` value if found and is a boolean, `null` otherwise

### `getTable()`

Get a nested table by key.

```zig
pub fn getTable(table: *const Table, key: []const u8) ?*const Table
```

**Returns:** Pointer to `Table` if found and is a table, `null` otherwise

**Example:**
```zig
if (zontom.getTable(&table, "database")) |db| {
    const host = zontom.getString(db, "host").?;
}
```

### `getArray()`

Get an array value by key.

```zig
pub fn getArray(table: *const Table, key: []const u8) ?*const Array
```

**Returns:** Pointer to `Array` if found and is an array, `null` otherwise

**Example:**
```zig
if (zontom.getArray(&table, "ports")) |ports| {
    for (ports.items.items) |item| {
        // Process array items
    }
}
```

### `getDatetime()`

Get a datetime value by key.

```zig
pub fn getDatetime(table: *const Table, key: []const u8) ?Datetime
```

**Returns:** `Datetime` struct if found and is a datetime, `null` otherwise

### `getPath()`

Get a value by dotted path notation.

```zig
pub fn getPath(table: *const Table, path: []const u8) ?Value
```

**Parameters:**
- `table`: Root table to search
- `path`: Dotted path (e.g., "server.database.host")

**Returns:** `Value` if found, `null` otherwise

**Example:**
```zig
if (zontom.getPath(&table, "server.database.host")) |value| {
    const host = value.string;
}
```

## Types

### `Table`

A TOML table (hash map of key-value pairs).

```zig
pub const Table = struct {
    map: std.StringArrayHashMap(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Table
    pub fn deinit(self: *Table) void
    pub fn put(self: *Table, key: []const u8, value: Value) !void
    pub fn get(self: *const Table, key: []const u8) ?Value
    pub fn getPtr(self: *Table, key: []const u8) ?*Value
};
```

### `Array`

A TOML array (list of values).

```zig
pub const Array = struct {
    items: std.ArrayList(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Array
    pub fn deinit(self: *Array, allocator: std.mem.Allocator) void
};
```

### `Value`

A TOML value (union of all possible types).

```zig
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

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void
};
```

### `Datetime`

A TOML datetime value (RFC 3339).

```zig
pub const Datetime = struct {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    nanosecond: u32,
    offset_minutes: ?i16,
};
```

### `ParseResult`

Result of parsing with context.

```zig
pub const ParseResult = struct {
    table: ?Table,
    error_context: ?ErrorContext,

    pub fn deinit(self: *ParseResult) void
};
```

### `ErrorContext`

Detailed error information.

```zig
pub const ErrorContext = struct {
    line: usize,
    column: usize,
    source_line: []const u8,
    message: []const u8,
    suggestion: ?[]const u8,
};
```

## Error Types

```zig
pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    DuplicateKey,
    InvalidValue,
    InvalidTable,
    InvalidArray,
    OutOfMemory,
};
```

## Memory Management

- All parsed data is owned by the `Table`
- Call `table.deinit()` to free all memory
- Strings returned by getters are owned by the table - do not free them
- If you need to keep a string after the table is freed, use `allocator.dupe()`

**Example:**
```zig
var table = try zontom.parse(allocator, source);
defer table.deinit();

// This string is valid while table exists
const name = zontom.getString(&table, "name").?;

// To keep it after table.deinit():
const name_copy = try allocator.dupe(u8, name);
defer allocator.free(name_copy);
```

## Best Practices

1. **Always use `defer table.deinit()`** immediately after parsing
2. **Check for null** when using getter functions
3. **Use `parseWithContext()`** in production for better error messages
4. **Use `getPath()`** for deeply nested values
5. **Don't free strings** returned by getters (they're owned by the table)

## Stringification (v0.2.0)

### `stringify()`

Convert a TOML table back to TOML format.

```zig
pub fn stringify(allocator: std.mem.Allocator, table: *const Table) ![]const u8
```

**Parameters:**
- `allocator`: Memory allocator for the output string
- `table`: Table to convert to TOML

**Returns:** TOML string (caller owns memory, must free)

**Example:**
```zig
var table = try zontom.parse(allocator, source);
defer table.deinit();

const toml_string = try zontom.stringify(allocator, &table);
defer allocator.free(toml_string);
```

### `stringifyWithOptions()`

Stringify with custom formatting options.

```zig
pub fn stringifyWithOptions(allocator: std.mem.Allocator, table: *const Table, options: FormatOptions) ![]const u8
```

**Parameters:**
- `allocator`: Memory allocator
- `table`: Table to stringify
- `options`: Formatting options

**Example:**
```zig
const options = zontom.FormatOptions{
    .indent = 4,
    .sort_keys = true,
    .blank_lines = false,
};

const toml_string = try zontom.stringifyWithOptions(allocator, &table, options);
defer allocator.free(toml_string);
```

### `FormatOptions`

Formatting options for stringification.

```zig
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
```

## Schema Validation (v0.2.0)

### `Schema`

Define a schema for validating TOML structure and types.

```zig
pub const Schema = struct {
    fields: []const FieldSchema,
    allow_unknown: bool = false,
    description: ?[]const u8 = null,

    pub fn validate(self: *const Schema, table: *const Table) ValidationResult
};
```

**Example:**
```zig
const schema = zontom.Schema{
    .fields = &[_]zontom.FieldSchema{
        .{ .name = "name", .field_type = .string, .required = true },
        .{ .name = "port", .field_type = .integer, .required = true,
           .constraints = &[_]zontom.Constraint{
               .{ .min_value = 1 },
               .{ .max_value = 65535 },
           },
        },
        .{ .name = "debug", .field_type = .boolean, .required = false },
    },
};

var result = schema.validate(&table);
defer result.deinit();

if (!result.valid) {
    for (result.errors.items) |err| {
        std.debug.print("Validation error: {s}\n", .{err});
    }
}
```

### `FieldSchema`

Schema definition for a single field.

```zig
pub const FieldSchema = struct {
    name: []const u8,
    field_type: ValueType,
    required: bool = false,
    default_value: ?Value = null,
    constraints: []const Constraint = &.{},
    description: ?[]const u8 = null,
    nested_schema: ?*const Schema = null,
};
```

### `ValueType`

Type enumeration for schema validation.

```zig
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
```

### `Constraint`

Validation constraints for field values.

```zig
pub const Constraint = union(enum) {
    min_value: i64,
    max_value: i64,
    min_length: usize,
    max_length: usize,
    pattern: []const u8,
    one_of: []const []const u8,
    custom: *const fn (value: *const Value) bool,
};
```

### `ValidationResult`

Result of schema validation.

```zig
pub const ValidationResult = struct {
    valid: bool,
    errors: std.ArrayList([]const u8),

    pub fn deinit(self: *ValidationResult) void
};
```

### `SchemaBuilder`

Builder pattern for creating schemas.

```zig
var builder = zontom.SchemaBuilder.init(allocator);
defer builder.deinit();

_ = try builder
    .addField(.{ .name = "name", .field_type = .string, .required = true })
    .addField(.{ .name = "port", .field_type = .integer, .required = true })
    .allowUnknown(true)
    .setDescription("Server configuration schema");

const schema = try builder.build();
defer allocator.free(schema.fields);
```

## See Also

- [Examples](EXAMPLES.md) - Practical usage examples
- [CLI Guide](CLI.md) - Command-line tool documentation
