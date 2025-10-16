# ZonTOM

**The cutting-edge TOML library for Zig 0.16.0**

ZonTOM is a complete, spec-compliant TOML 1.0.0 parser for Zig with beautiful error messages and a clean, idiomatic API.

## Features

- ✅ **Full TOML 1.0.0 Support** - Parses all TOML features including tables, arrays, inline tables, and more
- ✅ **Beautiful Error Messages** - Line/column info with source context and helpful suggestions
- ✅ **Stringify (v0.2.0)** - Convert TOML tables back to formatted TOML strings
- ✅ **Schema Validation (v0.2.0)** - Validate TOML structure and types with custom constraints
- ✅ **CLI Tool** - Validate and parse TOML files from the command line
- ✅ **Clean API** - Intuitive getter functions for all TOML types
- ✅ **Well Tested** - Comprehensive test suite covering edge cases
- ✅ **Zero Dependencies** - Core library has no external dependencies
- ⚡ **Fast** - Efficient lexer and parser design

## Quick Start

### As a Library

```zig
const std = @import("std");
const zontom = @import("zontom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const toml_source =
        \\\\[package]
        \\\\name = "myproject"
        \\\\version = "0.1.0"
    ;

    // Parse TOML
    var table = try zontom.parse(allocator, toml_source);
    defer table.deinit();

    // Access values
    const package = zontom.getTable(&table, "package").?;
    const name = zontom.getString(package, "name").?;

    std.debug.print("Project: {s}\\n", .{name});
}
```

**NEW in v0.2.0 - Stringify:**
```zig
// Convert table back to TOML
const toml_string = try zontom.stringify(allocator, &table);
defer allocator.free(toml_string);

// With formatting options
const formatted = try zontom.stringifyWithOptions(allocator, &table, .{
    .sort_keys = true,
    .indent = 4,
});
defer allocator.free(formatted);
```

**NEW in v0.2.0 - Schema Validation:**
```zig
// Define schema
const schema = zontom.Schema{
    .fields = &[_]zontom.FieldSchema{
        .{ .name = "name", .field_type = .string, .required = true },
        .{ .name = "port", .field_type = .integer, .required = true,
           .constraints = &[_]zontom.Constraint{
               .{ .min_value = 1 },
               .{ .max_value = 65535 },
           },
        },
    },
};

// Validate
var result = schema.validate(&table);
defer result.deinit();

if (!result.valid) {
    for (result.errors.items) |err| {
        std.debug.print("Error: {s}\\n", .{err});
    }
}
```

### As a CLI Tool

```bash
# Parse and display TOML structure
zontom parse config.toml

# Validate TOML syntax
zontom validate config.toml

# Quiet validation
zontom validate config.toml -q

# Verbose mode
zontom parse example.toml -v
```

## Installation

```bash
# Build the library and CLI
zig build

# Run tests
zig build test

# Install CLI tool
zig build install --prefix ~/.local
```

## Documentation

See [docs/](docs/) for full API documentation and examples.

## License

MIT License
