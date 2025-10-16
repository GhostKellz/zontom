//! Example: Web Server Configuration with Schema Validation
//!
//! This example shows:
//! - Complex nested configuration
//! - Schema validation with constraints
//! - Array of tables (routes)
//! - Manual field access vs parseInto

const std = @import("std");
const zontom = @import("zontom");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Web Server Config Validator ===\n\n", .{});

    // Read config file
    const file = try std.fs.cwd().openFile("examples/web-server-config/server.toml", .{});
    defer file.close();

    const stat = try file.stat();
    const source = try allocator.alloc(u8, stat.size);
    defer allocator.free(source);
    _ = try file.readAll(source);

    // Parse TOML
    var table = try zontom.parse(allocator, source);
    defer table.deinit();

    std.debug.print("✓ Parsed configuration successfully\n\n", .{});

    // Define schema with validation rules
    const schema = zontom.Schema{
        .fields = &[_]zontom.FieldSchema{
            .{
                .name = "server",
                .field_type = .table,
                .required = true,
                .description = "Server configuration",
            },
            .{
                .name = "database",
                .field_type = .table,
                .required = true,
                .description = "Database connection settings",
            },
            .{
                .name = "logging",
                .field_type = .table,
                .required = true,
            },
            .{
                .name = "routes",
                .field_type = .array,
                .required = true,
                .description = "API route definitions",
            },
            .{
                .name = "cache",
                .field_type = .table,
                .required = false,
            },
            .{
                .name = "security",
                .field_type = .table,
                .required = false,
            },
        },
        .allow_unknown = false,
    };

    // Validate
    std.debug.print("Validating configuration...\n", .{});
    var result = schema.validate(&table);
    defer result.deinit();

    if (!result.valid) {
        std.debug.print("❌ Validation failed:\n", .{});
        for (result.errors.items) |err| {
            std.debug.print("  - {s}\n", .{err});
        }
        return;
    }

    std.debug.print("✓ Configuration is valid\n\n", .{});

    // Access configuration values
    const server = zontom.getTable(&table, "server").?;
    const host = zontom.getString(server, "host").?;
    const port = zontom.getInt(server, "port").?;
    const workers = zontom.getInt(server, "workers").?;

    std.debug.print("Server Configuration:\n", .{});
    std.debug.print("  Host: {s}\n", .{host});
    std.debug.print("  Port: {d}\n", .{port});
    std.debug.print("  Workers: {d}\n\n", .{workers});

    // Check SSL configuration
    if (zontom.getTable(server, "ssl")) |ssl| {
        const enabled = zontom.getBool(ssl, "enabled").?;
        std.debug.print("SSL Configuration:\n", .{});
        std.debug.print("  Enabled: {}\n", .{enabled});

        if (enabled) {
            const cert = zontom.getString(ssl, "cert_file").?;
            const key = zontom.getString(ssl, "key_file").?;
            std.debug.print("  Certificate: {s}\n", .{cert});
            std.debug.print("  Key: {s}\n", .{key});

            if (zontom.getArray(ssl, "protocols")) |protocols| {
                std.debug.print("  Protocols: ", .{});
                for (protocols.items.items) |proto| {
                    std.debug.print("{s} ", .{proto.string});
                }
                std.debug.print("\n", .{});
            }
        }
        std.debug.print("\n", .{});
    }

    // List routes
    if (zontom.getArray(&table, "routes")) |routes| {
        std.debug.print("API Routes ({d} total):\n", .{routes.items.items.len});
        for (routes.items.items) |route_val| {
            const route = route_val.table;
            const path = zontom.getString(route, "path").?;
            const method = zontom.getString(route, "method").?;
            const handler = zontom.getString(route, "handler").?;
            const auth = zontom.getBool(route, "auth_required") orelse false;

            std.debug.print("  {s} {s} -> {s} ", .{ method, path, handler });
            if (auth) {
                std.debug.print("🔒\n", .{});
            } else {
                std.debug.print("🌐\n", .{});
            }
        }
        std.debug.print("\n", .{});
    }

    // Database info
    const db = zontom.getTable(&table, "database").?;
    const db_host = zontom.getString(db, "host").?;
    const db_port = zontom.getInt(db, "port").?;
    const db_name = zontom.getString(db, "database").?;
    const pool_size = zontom.getInt(db, "pool_size").?;

    std.debug.print("Database Configuration:\n", .{});
    std.debug.print("  Connection: {s}:{d}\n", .{ db_host, db_port });
    std.debug.print("  Database: {s}\n", .{db_name});
    std.debug.print("  Pool Size: {d}\n\n", .{pool_size});

    // Export to JSON
    std.debug.print("Exporting to JSON...\n", .{});
    const json = try zontom.toJSONPretty(allocator, &table, 2);
    defer allocator.free(json);

    // Save JSON to file
    const json_file = try std.fs.cwd().createFile("examples/web-server-config/server.json", .{});
    defer json_file.close();
    try json_file.writeAll(json);

    std.debug.print("✓ Exported to server.json\n\n", .{});

    std.debug.print("=== Configuration validated and exported successfully ===\n", .{});
}
