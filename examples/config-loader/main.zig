//! Example: Configuration loader using ZonTOM
//!
//! This example demonstrates how to:
//! - Define a configuration struct
//! - Load TOML config with parseInto
//! - Validate with auto-generated schema
//! - Export to JSON

const std = @import("std");
const zontom = @import("zontom");

const ServerConfig = struct {
    host: []const u8,
    port: i64,
    workers: i64 = 4,
    debug: bool = false,
};

const DatabaseConfig = struct {
    host: []const u8,
    port: i64,
    database: []const u8,
    max_connections: i64 = 10,
};

const AppConfig = struct {
    name: []const u8,
    version: []const u8,
    server: ServerConfig,
    database: DatabaseConfig,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config_toml =
        \\name = "MyApp"
        \\version = "1.0.0"
        \\
        \\[server]
        \\host = "0.0.0.0"
        \\port = 8080
        \\workers = 8
        \\debug = true
        \\
        \\[database]
        \\host = "localhost"
        \\port = 5432
        \\database = "myapp_db"
        \\max_connections = 20
    ;

    std.debug.print("=== ZonTOM Config Loader Example ===\n\n", .{});

    // 1. Parse TOML into struct
    std.debug.print("1. Loading configuration...\n", .{});
    const config = try zontom.parseInto(AppConfig, allocator, config_toml);
    defer zontom.freeDeserialized(AppConfig, allocator, config);

    std.debug.print("   ✓ Loaded: {s} v{s}\n", .{ config.name, config.version });
    std.debug.print("   ✓ Server: {s}:{d} (workers: {d}, debug: {})\n", .{
        config.server.host,
        config.server.port,
        config.server.workers,
        config.server.debug,
    });
    std.debug.print("   ✓ Database: {s}@{s}:{d} (max conn: {d})\n\n", .{
        config.database.database,
        config.database.host,
        config.database.port,
        config.database.max_connections,
    });

    // 2. Validate with auto-generated schema
    std.debug.print("2. Validating configuration with auto-schema...\n", .{});
    var table = try zontom.parse(allocator, config_toml);
    defer table.deinit();

    const schema = try zontom.schemaFrom(AppConfig, allocator);
    defer allocator.free(schema.fields);

    var result = schema.validate(&table);
    defer result.deinit();

    if (result.valid) {
        std.debug.print("   ✓ Configuration is valid!\n\n", .{});
    } else {
        std.debug.print("   ✗ Validation errors:\n", .{});
        for (result.errors.items) |err| {
            std.debug.print("     - {s}\n", .{err});
        }
        return;
    }

    // 3. Export to JSON
    std.debug.print("3. Converting to JSON...\n", .{});
    const json = try zontom.toJSONPretty(allocator, &table, 2);
    defer allocator.free(json);

    std.debug.print("   JSON output:\n", .{});
    std.debug.print("{s}\n", .{json});

    // 4. Re-stringify to TOML with formatting
    std.debug.print("4. Re-formatting as TOML (sorted keys)...\n", .{});
    const formatted = try zontom.stringifyWithOptions(allocator, &table, .{
        .sort_keys = true,
        .indent = 4,
    });
    defer allocator.free(formatted);

    std.debug.print("   Formatted TOML:\n", .{});
    std.debug.print("{s}\n", .{formatted});

    std.debug.print("=== Example Complete ===\n", .{});
}
