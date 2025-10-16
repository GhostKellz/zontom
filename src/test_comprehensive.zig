//! Comprehensive test suite for ZonTOM parser
const std = @import("std");
const testing = std.testing;
const zontom = @import("root.zig");

// Edge Cases

test "empty file" {
    const source = "";
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    try testing.expectEqual(@as(usize, 0), table.map.count());
}

test "only comments" {
    const source =
        \\# This is a comment
        \\# Another comment
        \\
        \\  # Indented comment
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    try testing.expectEqual(@as(usize, 0), table.map.count());
}

test "only whitespace" {
    const source = "   \n\n  \t\n   ";
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    try testing.expectEqual(@as(usize, 0), table.map.count());
}

test "strings with special characters" {
    const source =
        \\title = "String with \"quotes\" and \n newline"
        \\path = "C:\\Users\\name\\file.txt"
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const title = zontom.getString(&table, "title");
    try testing.expect(title != null);
}

test "multiline basic string" {
    const source =
        \\text = """
        \\First line
        \\Second line
        \\Third line"""
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const text = zontom.getString(&table, "text");
    try testing.expect(text != null);
}

test "literal strings" {
    const source =
        \\path = 'C:\Users\name\file.txt'
        \\regex = 'I [dw]on''t need \d{2} apples'
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const path = zontom.getString(&table, "path");
    try testing.expect(path != null);
}

test "integers with underscores" {
    const source =
        \\big_number = 1_000_000
        \\small = 1_2_3
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const big = zontom.getInt(&table, "big_number");
    try testing.expectEqual(@as(i64, 1000000), big.?);

    const small = zontom.getInt(&table, "small");
    try testing.expectEqual(@as(i64, 123), small.?);
}

test "floats with underscores" {
    const source =
        \\pi = 3.14_15_93
        \\big = 1_000.5
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const pi = zontom.getFloat(&table, "pi");
    try testing.expect(pi != null);
}

test "scientific notation" {
    const source =
        \\small = 1e-10
        \\big = 5e+22
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const small = zontom.getFloat(&table, "small");
    try testing.expect(small != null);

    const big = zontom.getFloat(&table, "big");
    try testing.expect(big != null);
}

test "boolean values" {
    const source =
        \\enabled = true
        \\disabled = false
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const enabled = zontom.getBool(&table, "enabled");
    try testing.expectEqual(true, enabled.?);

    const disabled = zontom.getBool(&table, "disabled");
    try testing.expectEqual(false, disabled.?);
}

test "datetime values" {
    const source =
        \\odt1 = 1979-05-27T07:32:00
        \\odt2 = 1979-05-27T00:32:00
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const dt1 = zontom.getDatetime(&table, "odt1");
    try testing.expect(dt1 != null);
    try testing.expectEqual(@as(u16, 1979), dt1.?.year);
    try testing.expectEqual(@as(u8, 5), dt1.?.month);
    try testing.expectEqual(@as(u8, 27), dt1.?.day);
}

test "empty arrays" {
    const source =
        \\empty = []
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const arr = zontom.getArray(&table, "empty");
    try testing.expect(arr != null);
    try testing.expectEqual(@as(usize, 0), arr.?.items.items.len);
}

test "mixed type arrays" {
    const source =
        \\numbers = [1, 2, 3, 4, 5]
        \\strings = ["a", "b", "c"]
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const numbers = zontom.getArray(&table, "numbers");
    try testing.expect(numbers != null);
    try testing.expectEqual(@as(usize, 5), numbers.?.items.items.len);
}

test "nested arrays deep" {
    const source =
        \\deep = [[[1, 2]], [[3, 4]]]
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const deep = zontom.getArray(&table, "deep");
    try testing.expect(deep != null);
}

test "arrays with trailing comma" {
    const source =
        \\arr = [
        \\  1,
        \\  2,
        \\  3,
        \\]
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const arr = zontom.getArray(&table, "arr");
    try testing.expect(arr != null);
    try testing.expectEqual(@as(usize, 3), arr.?.items.items.len);
}

test "inline tables" {
    const source =
        \\point = { x = 1, y = 2, z = 3 }
        \\name = { first = "Tom", last = "Preston-Werner" }
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const point = zontom.getTable(&table, "point");
    try testing.expect(point != null);

    const x = zontom.getInt(point.?, "x");
    try testing.expectEqual(@as(i64, 1), x.?);
}

test "empty inline table" {
    const source =
        \\empty = {}
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const empty = zontom.getTable(&table, "empty");
    try testing.expect(empty != null);
    try testing.expectEqual(@as(usize, 0), empty.?.map.count());
}

test "dotted keys simple" {
    const source =
        \\name.first = "Tom"
        \\name.last = "Preston-Werner"
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const name = zontom.getTable(&table, "name");
    try testing.expect(name != null);

    const first = zontom.getString(name.?, "first");
    try testing.expectEqualStrings("Tom", first.?);
}

test "dotted keys deep" {
    const source =
        \\a.b.c.d.e = "deep"
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const val = zontom.getPath(&table, "a.b.c.d.e");
    try testing.expect(val != null);
    try testing.expectEqualStrings("deep", val.?.string);
}

test "table sections" {
    const source =
        \\[package]
        \\name = "zontom"
        \\version = "0.1.0"
        \\
        \\[dependencies]
        \\zlog = "0.1.0"
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const package = zontom.getTable(&table, "package");
    try testing.expect(package != null);

    const deps = zontom.getTable(&table, "dependencies");
    try testing.expect(deps != null);
}

test "nested table sections" {
    const source =
        \\[a.b.c]
        \\key = "value"
        \\
        \\[a.b.d]
        \\key2 = "value2"
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const a = zontom.getTable(&table, "a");
    try testing.expect(a != null);
}

test "array of tables" {
    const source =
        \\[[products]]
        \\name = "Hammer"
        \\sku = 738594937
        \\
        \\[[products]]
        \\name = "Nail"
        \\sku = 284758393
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const products = zontom.getArray(&table, "products");
    try testing.expect(products != null);
    try testing.expectEqual(@as(usize, 2), products.?.items.items.len);
}

test "keys with underscores and dashes" {
    const source =
        \\bare_key = "value"
        \\bare-key = "value"
        \\_underscore = "value"
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    try testing.expect(table.get("bare_key") != null);
    try testing.expect(table.get("bare-key") != null);
    try testing.expect(table.get("_underscore") != null);
}

test "comments inline" {
    const source =
        \\key = "value" # This is a comment
        \\number = 42 # Another comment
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const key = zontom.getString(&table, "key");
    try testing.expectEqualStrings("value", key.?);
}

test "multiline arrays with comments" {
    const source =
        \\arr = [
        \\  1, # first
        \\  2, # second
        \\  3  # third
        \\]
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const arr = zontom.getArray(&table, "arr");
    try testing.expect(arr != null);
}

// Real-world examples

test "cargo.toml style" {
    const source =
        \\[package]
        \\name = "myproject"
        \\version = "0.1.0"
        \\edition = "2021"
        \\
        \\[dependencies]
        \\serde = "1.0"
        \\tokio = { version = "1.0", features = ["full"] }
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const package = zontom.getTable(&table, "package");
    try testing.expect(package != null);
}

test "pyproject.toml style" {
    const source =
        \\[project]
        \\name = "myproject"
        \\version = "0.1.0"
        \\description = "A sample project"
        \\
        \\[project.urls]
        \\homepage = "https://example.com"
        \\repository = "https://github.com/user/repo"
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const project = zontom.getTable(&table, "project");
    try testing.expect(project != null);
}
