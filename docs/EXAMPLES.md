# ZonTOM Examples

Practical examples for using ZonTOM in your projects.

## Basic Usage

### Parsing a Simple TOML File

```zig
const std = @import("std");
const zontom = @import("zontom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const toml =
        \\\\title = "My Application"
        \\\\version = "1.0.0"
        \\\\debug = true
    ;

    var table = try zontom.parse(allocator, toml);
    defer table.deinit();

    const title = zontom.getString(&table, "title").?;
    const version = zontom.getString(&table, "version").?;
    const debug = zontom.getBool(&table, "debug").?;

    std.debug.print("{s} v{s} (debug: {})\\n", .{ title, version, debug });
}
```

## String Types

### Basic Strings

Basic strings support escape sequences for special characters:

```zig
const toml =
    \\message = "Hello\tWorld!\nThis has a \"quoted\" word."
    \\path = "C:\\Users\\name\\file.txt"
;

var table = try zontom.parse(allocator, toml);
defer table.deinit();

const message = zontom.getString(&table, "message").?;
// Output: Hello    World!
//         This has a "quoted" word.
```

Supported escape sequences:
- `\b` - Backspace
- `\t` - Tab
- `\n` - Newline
- `\f` - Form feed
- `\r` - Carriage return
- `\"` - Quote
- `\\` - Backslash
- `\uXXXX` - Unicode (4 hex digits)
- `\UXXXXXXXX` - Unicode (8 hex digits)

### Literal Strings

Literal strings use single quotes and don't process escape sequences:

```zig
const toml =
    \\path = 'C:\Users\name\file.txt'
    \\regex = 'I [dw]on''t need \d{2} apples'
;

var table = try zontom.parse(allocator, toml);
defer table.deinit();

const path = zontom.getString(&table, "path").?;
// Output: C:\Users\name\file.txt (backslashes preserved)
```

### Multiline Basic Strings

Multiline basic strings use triple quotes (`"""`) and support all escape sequences:

```zig
const toml =
    \\description = """
    \\This is a multiline string.
    \\It can span multiple lines.
    \\
    \\Escape sequences like \t (tab) work here.
    \\You can include "quotes" without escaping."""
;

var table = try zontom.parse(allocator, toml);
defer table.deinit();

const desc = zontom.getString(&table, "description").?;
// The first newline after opening """ is automatically trimmed
```

**Important behaviors:**
- The first newline after opening `"""` is automatically trimmed
- All escape sequences are processed
- Newlines are preserved unless escaped
- Whitespace is preserved

### Multiline Literal Strings

Multiline literal strings use triple single quotes (`'''`) and preserve everything literally:

```zig
const toml =
    \\regex = '''
    \\I [dw]on't need \d{2} apples
    \\C:\Users\path\file.txt
    \\No escape processing: \n \t \\ remain as-is'''
;

var table = try zontom.parse(allocator, toml);
defer table.deinit();

const regex = zontom.getString(&table, "regex").?;
// Output preserves all backslashes literally
```

### Line-Ending Backslash

In multiline basic strings, a backslash at the end of a line trims the newline and all following whitespace:

```zig
const toml =
    \\message = """
    \\The quick brown \
    \\fox jumps over \
    \\the lazy dog."""
;

var table = try zontom.parse(allocator, toml);
defer table.deinit();

const message = zontom.getString(&table, "message").?;
// Output: "The quick brown fox jumps over the lazy dog."
// All line breaks and indentation removed
```

This is useful for breaking long text across multiple lines in your TOML file while keeping it as a single line in the parsed value.

### Practical Multiline String Examples

**SQL Query:**
```zig
const toml =
    \\query = """
    \\SELECT users.name, users.email, orders.total
    \\FROM users
    \\JOIN orders ON users.id = orders.user_id
    \\WHERE orders.status = 'completed'
    \\ORDER BY orders.total DESC"""
;

var table = try zontom.parse(allocator, toml);
defer table.deinit();
const query = zontom.getString(&table, "query").?;
// Newlines preserved for readability
```

**Configuration Description:**
```zig
const toml =
    \\help_text = """
    \\Usage: myapp [OPTIONS] <file>
    \\
    \\Options:
    \\  -v, --verbose    Enable verbose output
    \\  -h, --help       Show this help message
    \\  -o, --output     Specify output file"""
;

var table = try zontom.parse(allocator, toml);
defer table.deinit();
const help = zontom.getString(&table, "help_text").?;
```

**Windows File Path (Literal):**
```zig
const toml =
    \\# Use literal string to avoid escaping backslashes
    \\install_path = '''C:\Program Files\MyApp\bin'''
    \\
    \\# Or use basic string with escaped backslashes
    \\install_path_alt = "C:\\Program Files\\MyApp\\bin"
;

var table = try zontom.parse(allocator, toml);
defer table.deinit();
const path1 = zontom.getString(&table, "install_path").?;
const path2 = zontom.getString(&table, "install_path_alt").?;
// Both produce the same result
```

**Long Text Formatting:**
```zig
const toml =
    \\# Without line-ending backslash (preserves newlines)
    \\poem = """
    \\Roses are red,
    \\Violets are blue,
    \\TOML is great,
    \\And so are you!"""
    \\
    \\# With line-ending backslash (creates single line)
    \\long_description = """
    \\This is a very long description that we want to break \
    \\across multiple lines in the TOML file for readability, \
    \\but it should appear as a single line when parsed."""
;

var table = try zontom.parse(allocator, toml);
defer table.deinit();

const poem = zontom.getString(&table, "poem").?;
// Contains newlines: "Roses are red,\nViolets are blue,\n..."

const desc = zontom.getString(&table, "long_description").?;
// Single line: "This is a very long description that we want to break across multiple lines..."
```

## Working with Files

### Loading Configuration from a File

```zig
const std = @import("std");
const zontom = @import("zontom");

const Config = struct {
    name: []const u8,
    port: i64,
    debug: bool,
    table: zontom.Table,

    pub fn deinit(self: *Config) void {
        self.table.deinit();
    }
};

pub fn loadConfig(allocator: std.mem.Allocator, path: []const u8) !Config {
    // Read file
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    const source = try allocator.alloc(u8, stat.size);
    defer allocator.free(source);

    _ = try file.readAll(source);

    // Parse TOML
    var table = try zontom.parse(allocator, source);
    errdefer table.deinit();

    // Extract config
    return Config{
        .name = zontom.getString(&table, "name") orelse "unnamed",
        .port = zontom.getInt(&table, "port") orelse 8080,
        .debug = zontom.getBool(&table, "debug") orelse false,
        .table = table,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var config = try loadConfig(allocator, "config.toml");
    defer config.deinit();

    std.debug.print("Starting {s} on port {d}\\n", .{ config.name, config.port });
}
```

## Nested Tables

### Accessing Nested Configuration

```zig
const toml =
    \\\\[server]
    \\\\host = "localhost"
    \\\\port = 8080
    \\\\
    \\\\[server.tls]
    \\\\enabled = true
    \\\\cert = "/path/to/cert.pem"
    \\\\key = "/path/to/key.pem"
;

var table = try zontom.parse(allocator, toml);
defer table.deinit();

// Method 1: Navigate manually
const server = zontom.getTable(&table, "server").?;
const host = zontom.getString(server, "host").?;
const port = zontom.getInt(server, "port").?;

const tls = zontom.getTable(server, "tls").?;
const tls_enabled = zontom.getBool(tls, "enabled").?;

// Method 2: Use dot notation
const host_alt = zontom.getPath(&table, "server.host").?.string;
const cert = zontom.getPath(&table, "server.tls.cert").?.string;

std.debug.print("Server: {s}:{d}\\n", .{ host, port });
std.debug.print("TLS: {} (cert: {s})\\n", .{ tls_enabled, cert });
```

## Arrays

### Working with Arrays

```zig
const toml =
    \\\\[database]
    \\\\hosts = ["db1.example.com", "db2.example.com", "db3.example.com"]
    \\\\ports = [5432, 5433, 5434]
;

var table = try zontom.parse(allocator, toml);
defer table.deinit();

const database = zontom.getTable(&table, "database").?;

// String array
const hosts = zontom.getArray(database, "hosts").?;
std.debug.print("Database hosts:\\n", .{});
for (hosts.items.items) |host| {
    std.debug.print("  - {s}\\n", .{host.string});
}

// Integer array
const ports = zontom.getArray(database, "ports").?;
std.debug.print("Ports: ", .{});
for (ports.items.items) |port| {
    std.debug.print("{d} ", .{port.integer});
}
std.debug.print("\\n", .{});
```

### Nested Arrays

```zig
const toml =
    \\\\matrix = [[1, 2, 3], [4, 5, 6], [7, 8, 9]]
;

var table = try zontom.parse(allocator, toml);
defer table.deinit();

const matrix = zontom.getArray(&table, "matrix").?;
for (matrix.items.items, 0..) |row, i| {
    std.debug.print("Row {d}: ", .{i});
    for (row.array.items.items) |val| {
        std.debug.print("{d} ", .{val.integer});
    }
    std.debug.print("\\n", .{});
}
```

## Array of Tables

### Processing Multiple Entries

```zig
const toml =
    \\\\[[users]]
    \\\\name = "Alice"
    \\\\email = "alice@example.com"
    \\\\admin = true
    \\\\
    \\\\[[users]]
    \\\\name = "Bob"
    \\\\email = "bob@example.com"
    \\\\admin = false
;

var table = try zontom.parse(allocator, toml);
defer table.deinit();

const users = zontom.getArray(&table, "users").?;
for (users.items.items) |user_value| {
    const user = user_value.table;
    const name = zontom.getString(user, "name").?;
    const email = zontom.getString(user, "email").?;
    const admin = zontom.getBool(user, "admin").?;

    std.debug.print("User: {s} <{s}> [admin: {}]\\n", .{ name, email, admin });
}
```

## Error Handling

### Graceful Error Handling

```zig
pub fn parseConfigSafe(allocator: std.mem.Allocator, source: []const u8) !void {
    var result = zontom.parseWithContext(allocator, source);
    defer result.deinit();

    if (result.error_context) |err| {
        std.debug.print("❌ Failed to parse configuration\\n\\n", .{});
        std.debug.print("Error at line {d}, column {d}:\\n", .{ err.line, err.column });
        std.debug.print("  {s}\\n", .{err.source_line});

        // Print caret
        std.debug.print("  ", .{});
        for (0..err.column - 1) |_| std.debug.print(" ", .{});
        std.debug.print("^\\n", .{});

        std.debug.print("  {s}\\n", .{err.message});

        if (err.suggestion) |hint| {
            std.debug.print("  Hint: {s}\\n", .{hint});
        }

        return error.ParseFailed;
    }

    var table = result.table.?;
    // Use table...
}
```

## Advanced Patterns

### Configuration Builder

```zig
const ServerConfig = struct {
    host: []const u8,
    port: i64,
    workers: i64,
    tls_enabled: bool,
    tls_cert: ?[]const u8,
    tls_key: ?[]const u8,

    pub fn fromToml(table: *const zontom.Table) !ServerConfig {
        const server = zontom.getTable(table, "server") orelse return error.MissingServerConfig;

        const tls = zontom.getTable(server, "tls");
        const tls_enabled = if (tls) |t| zontom.getBool(t, "enabled") orelse false else false;

        return ServerConfig{
            .host = zontom.getString(server, "host") orelse "0.0.0.0",
            .port = zontom.getInt(server, "port") orelse 8080,
            .workers = zontom.getInt(server, "workers") orelse 4,
            .tls_enabled = tls_enabled,
            .tls_cert = if (tls) |t| zontom.getString(t, "cert") else null,
            .tls_key = if (tls) |t| zontom.getString(t, "key") else null,
        };
    }
};
```

### Dynamic Configuration Validation

```zig
fn validateConfig(table: *const zontom.Table) !void {
    // Required fields
    if (zontom.getString(table, "name") == null) {
        return error.MissingName;
    }

    // Type validation
    if (zontom.getInt(table, "port")) |port| {
        if (port < 1 or port > 65535) {
            return error.InvalidPort;
        }
    }

    // Conditional requirements
    if (zontom.getBool(table, "use_database") orelse false) {
        if (zontom.getTable(table, "database") == null) {
            return error.MissingDatabaseConfig;
        }
    }
}
```

## Real-World Example: Database Pool Config

```zig
const PoolConfig = struct {
    database: []const u8,
    user: []const u8,
    password: []const u8,
    hosts: [][]const u8,
    max_connections: i64,
    timeout_seconds: i64,
    allocator: std.mem.Allocator,

    pub fn fromFile(allocator: std.mem.Allocator, path: []const u8) !PoolConfig {
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const stat = try file.stat();
        const source = try allocator.alloc(u8, stat.size);
        defer allocator.free(source);
        _ = try file.readAll(source);

        var result = zontom.parseWithContext(allocator, source);
        defer result.deinit();

        if (result.error_context) |err| {
            std.debug.print("Config error at line {d}: {s}\\n", .{ err.line, err.message });
            return error.InvalidConfig;
        }

        const table = result.table.?;
        const db = zontom.getTable(&table, "database") orelse return error.MissingDatabaseConfig;

        // Extract hosts array
        const hosts_array = zontom.getArray(db, "hosts") orelse return error.MissingHosts;
        const hosts = try allocator.alloc([]const u8, hosts_array.items.items.len);
        for (hosts_array.items.items, 0..) |host, i| {
            hosts[i] = try allocator.dupe(u8, host.string);
        }

        return PoolConfig{
            .database = try allocator.dupe(u8, zontom.getString(db, "database") orelse return error.MissingDatabase),
            .user = try allocator.dupe(u8, zontom.getString(db, "user") orelse return error.MissingUser),
            .password = try allocator.dupe(u8, zontom.getString(db, "password") orelse return error.MissingPassword),
            .hosts = hosts,
            .max_connections = zontom.getInt(db, "max_connections") orelse 10,
            .timeout_seconds = zontom.getInt(db, "timeout_seconds") orelse 30,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *PoolConfig) void {
        self.allocator.free(self.database);
        self.allocator.free(self.user);
        self.allocator.free(self.password);
        for (self.hosts) |host| {
            self.allocator.free(host);
        }
        self.allocator.free(self.hosts);
    }
};
```

## Stringification (v0.2.0)

### Converting Tables Back to TOML

```zig
const std = @import("std");
const zontom = @import("zontom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse TOML
    const source =
        \\\\[package]
        \\\\name = "myproject"
        \\\\version = "1.0.0"
        \\\\
        \\\\[dependencies]
        \\\\zontom = "0.2.0"
    ;

    var table = try zontom.parse(allocator, source);
    defer table.deinit();

    // Convert back to TOML
    const toml_string = try zontom.stringify(allocator, &table);
    defer allocator.free(toml_string);

    std.debug.print("TOML Output:\n{s}\n", .{toml_string});
}
```

### Custom Formatting

```zig
// Use custom formatting options
const options = zontom.FormatOptions{
    .indent = 4,              // 4 spaces per indent level
    .use_spaces = true,       // Use spaces instead of tabs
    .blank_lines = true,      // Add blank lines between sections
    .sort_keys = true,        // Sort keys alphabetically
    .inline_table_threshold = 3,  // Max keys for inline tables
};

const formatted = try zontom.stringifyWithOptions(allocator, &table, options);
defer allocator.free(formatted);
```

### Round-Trip Conversion

```zig
// Parse TOML from file
const file = try std.fs.cwd().openFile("config.toml", .{});
defer file.close();

const stat = try file.stat();
const source = try allocator.alloc(u8, stat.size);
defer allocator.free(source);
_ = try file.readAll(source);

var table = try zontom.parse(allocator, source);
defer table.deinit();

// Modify the table
const package = zontom.getTable(&table, "package").?;
// ... make modifications ...

// Write back to TOML
const updated_toml = try zontom.stringify(allocator, &table);
defer allocator.free(updated_toml);

const out_file = try std.fs.cwd().createFile("config_new.toml", .{});
defer out_file.close();
try out_file.writeAll(updated_toml);
```

## Schema Validation (v0.2.0)

### Basic Schema Validation

```zig
const std = @import("std");
const zontom = @import("zontom");

pub fn validateServerConfig(allocator: std.mem.Allocator, config_path: []const u8) !void {
    // Read config file
    const file = try std.fs.cwd().openFile(config_path, .{});
    defer file.close();

    const stat = try file.stat();
    const source = try allocator.alloc(u8, stat.size);
    defer allocator.free(source);
    _ = try file.readAll(source);

    // Parse TOML
    var table = try zontom.parse(allocator, source);
    defer table.deinit();

    // Define schema
    const schema = zontom.Schema{
        .fields = &[_]zontom.FieldSchema{
            .{
                .name = "host",
                .field_type = .string,
                .required = true,
                .constraints = &[_]zontom.Constraint{
                    .{ .min_length = 1 },
                },
            },
            .{
                .name = "port",
                .field_type = .integer,
                .required = true,
                .constraints = &[_]zontom.Constraint{
                    .{ .min_value = 1 },
                    .{ .max_value = 65535 },
                },
            },
            .{
                .name = "debug",
                .field_type = .boolean,
                .required = false,
            },
        },
    };

    // Validate
    var result = schema.validate(&table);
    defer result.deinit();

    if (!result.valid) {
        std.debug.print("❌ Configuration validation failed:\n", .{});
        for (result.errors.items) |err| {
            std.debug.print("  - {s}\n", .{err});
        }
        return error.InvalidConfig;
    }

    std.debug.print("✓ Configuration is valid\n", .{});
}
```

### Using SchemaBuilder

```zig
const std = @import("std");
const zontom = @import("zontom");

fn createDatabaseSchema(allocator: std.mem.Allocator) !zontom.Schema {
    var builder = zontom.SchemaBuilder.init(allocator);
    defer builder.deinit();

    _ = try builder
        .setDescription("Database configuration schema")
        .addField(.{
            .name = "host",
            .field_type = .string,
            .required = true,
            .description = "Database host address",
        })
        .addField(.{
            .name = "port",
            .field_type = .integer,
            .required = true,
            .constraints = &[_]zontom.Constraint{
                .{ .min_value = 1 },
                .{ .max_value = 65535 },
            },
        })
        .addField(.{
            .name = "database",
            .field_type = .string,
            .required = true,
            .constraints = &[_]zontom.Constraint{
                .{ .min_length = 1 },
            },
        })
        .addField(.{
            .name = "ssl_mode",
            .field_type = .string,
            .required = false,
            .constraints = &[_]zontom.Constraint{
                .{ .one_of = &[_][]const u8{ "disable", "require", "verify-ca", "verify-full" } },
            },
        })
        .allowUnknown(false);

    return try builder.build();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const schema = try createDatabaseSchema(allocator);
    defer allocator.free(schema.fields);

    const config =
        \\\\host = "localhost"
        \\\\port = 5432
        \\\\database = "myapp"
        \\\\ssl_mode = "require"
    ;

    var table = try zontom.parse(allocator, config);
    defer table.deinit();

    var result = schema.validate(&table);
    defer result.deinit();

    if (result.valid) {
        std.debug.print("✓ Database config is valid\n", .{});
    }
}
```

### Nested Schema Validation

```zig
// Define nested schemas for complex configurations
const server_ssl_schema = zontom.Schema{
    .fields = &[_]zontom.FieldSchema{
        .{ .name = "enabled", .field_type = .boolean, .required = true },
        .{ .name = "cert", .field_type = .string, .required = false },
        .{ .name = "key", .field_type = .string, .required = false },
    },
};

const server_schema = zontom.Schema{
    .fields = &[_]zontom.FieldSchema{
        .{ .name = "host", .field_type = .string, .required = true },
        .{ .name = "port", .field_type = .integer, .required = true },
        .{
            .name = "ssl",
            .field_type = .table,
            .required = false,
            .nested_schema = &server_ssl_schema,
        },
    },
};
```

### Custom Validation Functions

```zig
fn validateEmail(value: *const zontom.Value) bool {
    if (value.* != .string) return false;
    const email = value.string;

    // Simple email validation
    return std.mem.indexOf(u8, email, "@") != null and
           std.mem.indexOf(u8, email, ".") != null;
}

const schema = zontom.Schema{
    .fields = &[_]zontom.FieldSchema{
        .{
            .name = "email",
            .field_type = .string,
            .required = true,
            .constraints = &[_]zontom.Constraint{
                .{ .custom = &validateEmail },
            },
        },
    },
};
```

## See Also

- [API Reference](API.md) - Complete API documentation
- [CLI Guide](CLI.md) - Command-line tool usage
