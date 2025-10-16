//! Benchmarking infrastructure for ZonTOM

const std = @import("std");
const zontom = @import("root.zig");

pub const BenchmarkResult = struct {
    name: []const u8,
    iterations: usize,
    total_ns: u64,
    avg_ns: u64,
    ops_per_sec: f64,

    pub fn print(self: BenchmarkResult) void {
        std.debug.print("  {s}:\n", .{self.name});
        std.debug.print("    Iterations: {d}\n", .{self.iterations});
        std.debug.print("    Total time: {d} ns ({d} ms)\n", .{ self.total_ns, self.total_ns / 1_000_000 });
        std.debug.print("    Average: {d} ns/op\n", .{self.avg_ns});
        std.debug.print("    Speed: {d:.2} ops/sec\n\n", .{self.ops_per_sec});
    }
};

pub fn benchmark(
    allocator: std.mem.Allocator,
    comptime name: []const u8,
    comptime func: fn (allocator: std.mem.Allocator) anyerror!void,
    iterations: usize,
) !BenchmarkResult {
    var timer = try std.time.Timer.start();
    const start = timer.read();

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        try func(allocator);
    }

    const end = timer.read();
    const total_ns = end - start;
    const avg_ns = total_ns / iterations;
    const ops_per_sec = @as(f64, @floatFromInt(iterations)) / (@as(f64, @floatFromInt(total_ns)) / 1_000_000_000.0);

    return BenchmarkResult{
        .name = name,
        .iterations = iterations,
        .total_ns = total_ns,
        .avg_ns = avg_ns,
        .ops_per_sec = ops_per_sec,
    };
}

// Benchmark cases

fn benchParseTiny(allocator: std.mem.Allocator) !void {
    const source = "name = \"test\"";
    var table = try zontom.parse(allocator, source);
    table.deinit();
}

fn benchParseSmall(allocator: std.mem.Allocator) !void {
    const source =
        \\[package]
        \\name = "zontom"
        \\version = "0.2.0"
        \\debug = false
        \\
        \\[dependencies]
        \\zlog = "0.1.0"
    ;
    var table = try zontom.parse(allocator, source);
    table.deinit();
}

fn benchParseMedium(allocator: std.mem.Allocator) !void {
    const source =
        \\[package]
        \\name = "myproject"
        \\version = "1.0.0"
        \\authors = ["Alice <alice@example.com>", "Bob <bob@example.com>"]
        \\
        \\[dependencies]
        \\lib1 = "1.0"
        \\lib2 = "2.5"
        \\lib3 = "3.1.4"
        \\
        \\[dev-dependencies]
        \\test-lib = "0.1"
        \\
        \\[[features]]
        \\name = "feature1"
        \\enabled = true
        \\
        \\[[features]]
        \\name = "feature2"
        \\enabled = false
        \\
        \\[build]
        \\target = "x86_64"
        \\optimize = "ReleaseFast"
        \\
        \\[server]
        \\host = "0.0.0.0"
        \\port = 8080
        \\workers = 4
        \\
        \\[server.ssl]
        \\enabled = true
        \\cert = "/path/to/cert.pem"
        \\key = "/path/to/key.pem"
    ;
    var table = try zontom.parse(allocator, source);
    table.deinit();
}

fn benchStringifySmall(allocator: std.mem.Allocator) !void {
    const source =
        \\name = "test"
        \\port = 8080
        \\enabled = true
    ;
    var table = try zontom.parse(allocator, source);
    defer table.deinit();

    const toml = try zontom.stringify(allocator, &table);
    allocator.free(toml);
}

fn benchDeserializeStruct(allocator: std.mem.Allocator) !void {
    const Config = struct {
        name: []const u8,
        port: i64,
        debug: bool = false,
    };

    const source =
        \\name = "app"
        \\port = 8080
    ;

    const config = try zontom.parseInto(Config, allocator, source);
    zontom.freeDeserialized(Config, allocator, config);
}

fn benchJSONConversion(allocator: std.mem.Allocator) !void {
    const source =
        \\[server]
        \\host = "localhost"
        \\port = 8080
        \\
        \\[database]
        \\host = "db.local"
        \\port = 5432
    ;

    var table = try zontom.parse(allocator, source);
    defer table.deinit();

    const json = try zontom.toJSON(allocator, &table);
    allocator.free(json);
}

pub fn runAllBenchmarks(allocator: std.mem.Allocator) !void {
    std.debug.print("\n=== ZonTOM Benchmarks ===\n\n", .{});

    const benchmarks = .{
        .{ "Parse: Tiny (1 key)", benchParseTiny, 10_000 },
        .{ "Parse: Small (6 keys)", benchParseSmall, 5_000 },
        .{ "Parse: Medium (25+ keys)", benchParseMedium, 1_000 },
        .{ "Stringify: Small", benchStringifySmall, 5_000 },
        .{ "Deserialize: Struct", benchDeserializeStruct, 5_000 },
        .{ "Convert: TOML to JSON", benchJSONConversion, 2_000 },
    };

    inline for (benchmarks) |bench_info| {
        const result = try benchmark(allocator, bench_info[0], bench_info[1], bench_info[2]);
        result.print();
    }

    std.debug.print("=== Benchmark Complete ===\n\n", .{});
}

test "run benchmarks" {
    const testing = std.testing;

    // Just run with minimal iterations for testing
    _ = try benchmark(testing.allocator, "test", benchParseTiny, 10);
}
