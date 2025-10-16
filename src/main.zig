//! ZonTOM CLI - TOML parser and validator
const std = @import("std");
const zontom = @import("zontom");
const zlog = @import("zlog");
const flash = @import("flash");
const flare = @import("flare");

const version_info = "0.1.0-dev";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create ZonTOM CLI
    const ZonTomCLI = flash.CLI(.{
        .name = "zontom",
        .version = version_info,
        .about = "ZonTOM - The cutting-edge TOML library for Zig 0.16.0",
        .subcommand_required = false,
    });

    // Define commands
    const parse_cmd = flash.cmd("parse", (flash.CommandConfig{})
        .withAbout("Parse and validate a TOML file")
        .withArgs(&.{
            flash.arg("file", (flash.ArgumentConfig{})
                .withHelp("Path to the TOML file")
                .setRequired()),
        })
        .withFlags(&.{
            flash.flag("verbose", (flash.FlagConfig{})
                .withShort('v')
                .withHelp("Enable verbose logging")),
        })
        .withHandler(parseHandler));

    const fmt_cmd = flash.cmd("fmt", (flash.CommandConfig{})
        .withAbout("Format a TOML file")
        .withArgs(&.{
            flash.arg("file", (flash.ArgumentConfig{})
                .withHelp("Path to the TOML file")
                .setRequired()),
        })
        .withFlags(&.{
            flash.flag("in-place", (flash.FlagConfig{})
                .withShort('i')
                .withHelp("Format file in-place (overwrite)")),
            flash.flag("sort-keys", (flash.FlagConfig{})
                .withShort('s')
                .withHelp("Sort keys alphabetically")),
            flash.flag("indent", (flash.FlagConfig{})
                .withHelp("Indent size (default: 2)")
                .withValue()),
        })
        .withHandler(fmtHandler));

    const validate_cmd = flash.cmd("validate", (flash.CommandConfig{})
        .withAbout("Validate TOML file syntax")
        .withArgs(&.{
            flash.arg("file", (flash.ArgumentConfig{})
                .withHelp("Path to the TOML file")
                .setRequired()),
        })
        .withFlags(&.{
            flash.flag("quiet", (flash.FlagConfig{})
                .withShort('q')
                .withHelp("Suppress output on success")),
        })
        .withHandler(validateHandler));

    // Create CLI with commands
    var cli = ZonTomCLI.init(allocator, (flash.CommandConfig{})
        .withAbout("A powerful TOML parser and validator for Zig")
        .withSubcommands(&.{ parse_cmd, fmt_cmd, validate_cmd })
        .withHandler(defaultHandler));

    try cli.run();
}

fn defaultHandler(ctx: flash.Context) flash.Error!void {
    std.debug.print("⚡ ZonTOM - The cutting-edge TOML library for Zig\n\n", .{});
    std.debug.print("Usage: zontom <command> [options]\n\n", .{});
    std.debug.print("Commands:\n", .{});
    std.debug.print("  parse <file>      Parse and display TOML file structure\n", .{});
    std.debug.print("  validate <file>   Validate TOML file syntax\n", .{});
    std.debug.print("  fmt <file>        Format a TOML file (coming soon)\n", .{});
    std.debug.print("\nExamples:\n", .{});
    std.debug.print("  zontom parse config.toml\n", .{});
    std.debug.print("  zontom validate config.toml -q\n", .{});
    std.debug.print("  zontom parse example.toml -v\n", .{});
    std.debug.print("\nFor more help: zontom help\n", .{});
    _ = ctx;
}

fn parseHandler(ctx: flash.Context) flash.Error!void {
    const file_path = ctx.getString("file") orelse return flash.Error.InvalidArgument;
    const verbose = ctx.getFlag("verbose");

    // Initialize logger
    var logger = zlog.Logger.init(ctx.allocator, .{
        .level = if (verbose) .debug else .info,
    }) catch |err| {
        std.debug.print("Warning: Failed to initialize logger: {s}\n", .{@errorName(err)});
        return flash.Error.ConfigError;
    };
    defer logger.deinit();

    logger.info("Parsing TOML file: {s}", .{file_path});

    // Read file
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        logger.err("Failed to open file: {s}", .{@errorName(err)});
        std.debug.print("❌ Error: Failed to open file '{s}': {s}\n", .{ file_path, @errorName(err) });
        return flash.Error.IOError;
    };
    defer file.close();

    const stat = file.stat() catch |err| {
        logger.err("Failed to stat file: {s}", .{@errorName(err)});
        std.debug.print("❌ Error: Failed to stat file: {s}\n", .{@errorName(err)});
        return flash.Error.IOError;
    };

    const source = ctx.allocator.alloc(u8, stat.size) catch |err| {
        logger.err("Failed to allocate memory: {s}", .{@errorName(err)});
        std.debug.print("❌ Error: Failed to allocate memory: {s}\n", .{@errorName(err)});
        return flash.Error.IOError;
    };
    defer ctx.allocator.free(source);

    _ = file.readAll(source) catch |err| {
        logger.err("Failed to read file: {s}", .{@errorName(err)});
        std.debug.print("❌ Error: Failed to read file: {s}\n", .{@errorName(err)});
        return flash.Error.IOError;
    };

    logger.debug("File size: {} bytes", .{source.len});

    // Parse TOML with detailed error reporting
    var parse_result = zontom.parseWithContext(ctx.allocator, source);
    defer parse_result.deinit();

    if (parse_result.error_context) |err_ctx| {
        logger.err("Failed to parse TOML", .{});
        std.debug.print("\n❌ Parse Error\n\n", .{});
        std.debug.print("Error at line {d}, column {d}:\n", .{ err_ctx.line, err_ctx.column });
        std.debug.print("  {s}\n", .{err_ctx.source_line});
        std.debug.print("  ", .{});
        for (0..err_ctx.column - 1) |_| {
            std.debug.print(" ", .{});
        }
        std.debug.print("^\n", .{});
        std.debug.print("  {s}\n", .{err_ctx.message});
        if (err_ctx.suggestion) |hint| {
            std.debug.print("  Hint: {s}\n", .{hint});
        }
        std.debug.print("\n", .{});
        return flash.Error.InvalidInput;
    }

    var table = parse_result.table.?;

    logger.info("Successfully parsed TOML file", .{});
    logger.info("Root table contains {} entries", .{table.map.count()});

    // Print summary
    std.debug.print("\n=== TOML Parse Summary ===\n", .{});
    std.debug.print("File: {s}\n", .{file_path});
    std.debug.print("Size: {} bytes\n", .{source.len});
    std.debug.print("Root entries: {}\n\n", .{table.map.count()});
    std.debug.print("Root keys:\n", .{});

    var it = table.map.keyIterator();
    while (it.next()) |key| {
        const val = table.get(key.*).?;
        const type_name = switch (val) {
            .string => "string",
            .integer => "integer",
            .float => "float",
            .boolean => "boolean",
            .datetime => "datetime",
            .date => "date",
            .time => "time",
            .array => "array",
            .table => "table",
        };
        std.debug.print("  ├─ {s}: {s}\n", .{ key.*, type_name });
    }

    std.debug.print("\n✓ Validation successful!\n", .{});
}

fn validateHandler(ctx: flash.Context) flash.Error!void {
    const file_path = ctx.getString("file") orelse return flash.Error.InvalidArgument;
    const quiet = ctx.getFlag("quiet");

    // Read file
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        if (!quiet) {
            std.debug.print("❌ Error: Failed to open file '{s}': {s}\n", .{ file_path, @errorName(err) });
        }
        return flash.Error.IOError;
    };
    defer file.close();

    const stat = file.stat() catch |err| {
        if (!quiet) {
            std.debug.print("❌ Error: Failed to stat file: {s}\n", .{@errorName(err)});
        }
        return flash.Error.IOError;
    };

    const source = ctx.allocator.alloc(u8, stat.size) catch |err| {
        if (!quiet) {
            std.debug.print("❌ Error: Failed to allocate memory: {s}\n", .{@errorName(err)});
        }
        return flash.Error.IOError;
    };
    defer ctx.allocator.free(source);

    _ = file.readAll(source) catch |err| {
        if (!quiet) {
            std.debug.print("❌ Error: Failed to read file: {s}\n", .{@errorName(err)});
        }
        return flash.Error.IOError;
    };

    // Parse TOML (validation) with detailed error reporting
    var parse_result = zontom.parseWithContext(ctx.allocator, source);
    defer parse_result.deinit();

    if (parse_result.error_context) |err_ctx| {
        if (!quiet) {
            std.debug.print("\n❌ Validation Failed\n\n", .{});
            std.debug.print("Error at line {d}, column {d}:\n", .{ err_ctx.line, err_ctx.column });
            std.debug.print("  {s}\n", .{err_ctx.source_line});
            std.debug.print("  ", .{});
            for (0..err_ctx.column - 1) |_| {
                std.debug.print(" ", .{});
            }
            std.debug.print("^\n", .{});
            std.debug.print("  {s}\n", .{err_ctx.message});
            if (err_ctx.suggestion) |hint| {
                std.debug.print("  Hint: {s}\n", .{hint});
            }
            std.debug.print("\n", .{});
        }
        return flash.Error.InvalidInput;
    }

    if (!quiet) {
        std.debug.print("✓ {s} is valid TOML\n", .{file_path});
    }
}

fn fmtHandler(ctx: flash.Context) flash.Error!void {
    const file_path = ctx.getString("file") orelse return flash.Error.InvalidArgument;
    const in_place = ctx.getFlag("in-place");
    const sort_keys = ctx.getFlag("sort-keys");
    const indent_str = ctx.getString("indent");

    const indent = if (indent_str) |s| std.fmt.parseInt(usize, s, 10) catch 2 else 2;

    // Read file
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        std.debug.print("❌ Error: Failed to open file '{s}': {s}\n", .{ file_path, @errorName(err) });
        return flash.Error.IOError;
    };
    defer file.close();

    const stat = file.stat() catch |err| {
        std.debug.print("❌ Error: Failed to stat file: {s}\n", .{@errorName(err)});
        return flash.Error.IOError;
    };

    const source = ctx.allocator.alloc(u8, stat.size) catch |err| {
        std.debug.print("❌ Error: Failed to allocate memory: {s}\n", .{@errorName(err)});
        return flash.Error.IOError;
    };
    defer ctx.allocator.free(source);

    _ = file.readAll(source) catch |err| {
        std.debug.print("❌ Error: Failed to read file: {s}\n", .{@errorName(err)});
        return flash.Error.IOError;
    };

    // Parse TOML
    var parse_result = zontom.parseWithContext(ctx.allocator, source);
    defer parse_result.deinit();

    if (parse_result.error_context) |err_ctx| {
        std.debug.print("\n❌ Format Failed - Invalid TOML\n\n", .{});
        std.debug.print("Error at line {d}, column {d}:\n", .{ err_ctx.line, err_ctx.column });
        std.debug.print("  {s}\n", .{err_ctx.source_line});
        std.debug.print("  ", .{});
        for (0..err_ctx.column - 1) |_| {
            std.debug.print(" ", .{});
        }
        std.debug.print("^\n", .{});
        std.debug.print("  {s}\n", .{err_ctx.message});
        if (err_ctx.suggestion) |hint| {
            std.debug.print("  Hint: {s}\n", .{hint});
        }
        std.debug.print("\n", .{});
        return flash.Error.InvalidInput;
    }

    var table = parse_result.table.?;

    // Format with options
    const options = zontom.FormatOptions{
        .indent = indent,
        .use_spaces = true,
        .blank_lines = true,
        .sort_keys = sort_keys,
    };

    const formatted = zontom.stringifyWithOptions(ctx.allocator, &table, options) catch |err| {
        std.debug.print("❌ Error: Failed to format TOML: {s}\n", .{@errorName(err)});
        return flash.Error.InvalidInput;
    };
    defer ctx.allocator.free(formatted);

    if (in_place) {
        // Write back to file
        const out_file = std.fs.cwd().createFile(file_path, .{}) catch |err| {
            std.debug.print("❌ Error: Failed to write file '{s}': {s}\n", .{ file_path, @errorName(err) });
            return flash.Error.IOError;
        };
        defer out_file.close();

        out_file.writeAll(formatted) catch |err| {
            std.debug.print("❌ Error: Failed to write file: {s}\n", .{@errorName(err)});
            return flash.Error.IOError;
        };

        std.debug.print("✓ Formatted {s}\n", .{file_path});
    } else {
        // Print to stdout
        std.debug.print("{s}", .{formatted});
    }
}

test "simple test" {
    const testing = std.testing;
    var list = std.ArrayList(i32){};
    defer list.deinit(testing.allocator);
    try list.append(testing.allocator, 42);
    try testing.expectEqual(@as(i32, 42), list.pop());
}
