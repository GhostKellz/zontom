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
    // Note: first newline after opening quotes should be trimmed
    try testing.expectEqualStrings("First line\nSecond line\nThird line", text.?);
}

test "multiline basic string with escape sequences" {
    const source =
        \\text = """
        \\Line with \t tab
        \\Line with \n newline escape
        \\Line with \" quotes
        \\Line with \\ backslash"""
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const text = zontom.getString(&table, "text");
    try testing.expect(text != null);
    try testing.expectEqualStrings("Line with \t tab\nLine with \n newline escape\nLine with \" quotes\nLine with \\ backslash", text.?);
}

test "multiline basic string with line-ending backslash" {
    const source =
        \\text = """
        \\The quick brown \
        \\fox jumps over \
        \\the lazy dog."""
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const text = zontom.getString(&table, "text");
    try testing.expect(text != null);
    // Line-ending backslash trims newline and following whitespace
    try testing.expectEqualStrings("The quick brown fox jumps over the lazy dog.", text.?);
}

test "multiline basic string first newline trimmed" {
    const source = "text = \"\"\"\nHello World\"\"\"";
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const text = zontom.getString(&table, "text");
    try testing.expect(text != null);
    // First newline after opening quotes is trimmed
    try testing.expectEqualStrings("Hello World", text.?);
}

test "multiline literal string" {
    const source =
        \\regex = '''
        \\I [dw]on't need \d{2} apples
        \\C:\Users\path\file.txt
        \\No escapes: \n \t \\'''
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const regex = zontom.getString(&table, "regex");
    try testing.expect(regex != null);
    // Literal strings preserve backslashes and don't process escapes
    try testing.expectEqualStrings("I [dw]on't need \\d{2} apples\nC:\\Users\\path\\file.txt\nNo escapes: \\n \\t \\\\", regex.?);
}

test "multiline literal string no escape processing" {
    const source =
        \\path = '''
        \\C:\Windows\System32\
        \\Special chars: \n \t \r
        \\Backslash: \\'''
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const path = zontom.getString(&table, "path");
    try testing.expect(path != null);
    // Literal strings don't process escape sequences
    try testing.expectEqualStrings("C:\\Windows\\System32\\\nSpecial chars: \\n \\t \\r\nBackslash: \\\\", path.?);
}

test "multiline string with quotes inside" {
    const source =
        \\text = """
        \\She said "hello" to me.
        \\He replied \"hi\"."""
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const text = zontom.getString(&table, "text");
    try testing.expect(text != null);
    try testing.expectEqualStrings("She said \"hello\" to me.\nHe replied \"hi\".", text.?);
}

test "multiline string empty content" {
    const source = "empty = \"\"\"\"\"\"";
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const empty = zontom.getString(&table, "empty");
    try testing.expect(empty != null);
    try testing.expectEqualStrings("", empty.?);
}

test "multiline string with only newlines" {
    const source =
        \\text = """
        \\
        \\
        \\"""
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const text = zontom.getString(&table, "text");
    try testing.expect(text != null);
    // First newline trimmed, two remain
    try testing.expectEqualStrings("\n\n", text.?);
}

test "multiline basic string with all escape types" {
    const source =
        \\escapes = """
        \\Backspace: \b
        \\Tab: \t
        \\Newline: \n
        \\Form feed: \f
        \\Carriage return: \r
        \\Quote: \"
        \\Backslash: \\"""
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const escapes = zontom.getString(&table, "escapes");
    try testing.expect(escapes != null);
    const expected = "Backspace: \x08\nTab: \t\nNewline: \n\nForm feed: \x0C\nCarriage return: \r\nQuote: \"\nBackslash: \\";
    try testing.expectEqualStrings(expected, escapes.?);
}

test "multiline string line-ending backslash complex" {
    const source =
        \\text = """
        \\Line 1 \
        \\    Line 2 with indent \
        \\        Line 3 more indent"""
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const text = zontom.getString(&table, "text");
    try testing.expect(text != null);
    // Line-ending backslash trims the newline and all following whitespace
    try testing.expectEqualStrings("Line 1 Line 2 with indent Line 3 more indent", text.?);
}

test "multiline string preserves internal whitespace" {
    const source =
        \\text = """
        \\  Indented line
        \\    More indented
        \\  Back to first level"""
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const text = zontom.getString(&table, "text");
    try testing.expect(text != null);
    try testing.expectEqualStrings("  Indented line\n    More indented\n  Back to first level", text.?);
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

test "number validation - invalid underscores" {
    // Leading underscore
    const leading = "num = _123";
    try testing.expectError(error.InvalidValue, zontom.parse(testing.allocator, leading));

    // Trailing underscore
    const trailing = "num = 123_";
    try testing.expectError(error.InvalidValue, zontom.parse(testing.allocator, trailing));

    // Consecutive underscores
    const consecutive = "num = 1__23";
    try testing.expectError(error.InvalidValue, zontom.parse(testing.allocator, consecutive));

    // Underscore next to decimal
    const next_to_decimal1 = "num = 1_.23";
    try testing.expectError(error.InvalidValue, zontom.parse(testing.allocator, next_to_decimal1));

    const next_to_decimal2 = "num = 1._23";
    try testing.expectError(error.InvalidValue, zontom.parse(testing.allocator, next_to_decimal2));

    // Underscore next to exponent
    const next_to_exp1 = "num = 1_e10";
    try testing.expectError(error.InvalidValue, zontom.parse(testing.allocator, next_to_exp1));

    const next_to_exp2 = "num = 1e_10";
    try testing.expectError(error.InvalidValue, zontom.parse(testing.allocator, next_to_exp2));
}

test "number validation - hex/octal/binary not allowed" {
    // Hex not allowed
    const hex = "num = 0xFF";
    try testing.expectError(error.InvalidValue, zontom.parse(testing.allocator, hex));

    // Octal not allowed
    const octal = "num = 0o755";
    try testing.expectError(error.InvalidValue, zontom.parse(testing.allocator, octal));

    // Binary not allowed
    const binary = "num = 0b1010";
    try testing.expectError(error.InvalidValue, zontom.parse(testing.allocator, binary));
}

test "number validation - leading zeros not allowed" {
    // Leading zeros in integers (except 0 itself)
    const leading_zero = "num = 007";
    try testing.expectError(error.InvalidValue, zontom.parse(testing.allocator, leading_zero));

    // But 0 alone is fine
    const zero = "num = 0";
    var table1 = try zontom.parse(testing.allocator, zero);
    defer table1.deinit();
    try testing.expectEqual(@as(i64, 0), zontom.getInt(&table1, "num").?);

    // And 0.5 is fine (float)
    const zero_float = "num = 0.5";
    var table2 = try zontom.parse(testing.allocator, zero_float);
    defer table2.deinit();
    try testing.expectEqual(@as(f64, 0.5), zontom.getFloat(&table2, "num").?);
}

test "valid number formats" {
    const source =
        \\positive = +99
        \\negative = -17
        \\zero = 0
        \\with_underscores = 5_349_221
        \\float_exp = 5e+22
        \\float_both = 6.626e-34
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    try testing.expectEqual(@as(i64, 99), zontom.getInt(&table, "positive").?);
    try testing.expectEqual(@as(i64, -17), zontom.getInt(&table, "negative").?);
    try testing.expectEqual(@as(i64, 0), zontom.getInt(&table, "zero").?);
    try testing.expectEqual(@as(i64, 5349221), zontom.getInt(&table, "with_underscores").?);
}

test "special float values" {
    const source =
        \\positive_inf = inf
        \\negative_inf = -inf
        \\explicit_positive_inf = +inf
        \\not_a_number = nan
        \\positive_nan = +nan
        \\negative_nan = -nan
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const pos_inf = zontom.getFloat(&table, "positive_inf").?;
    try testing.expect(std.math.isInf(pos_inf));
    try testing.expect(std.math.isPositiveInf(pos_inf));

    const neg_inf = zontom.getFloat(&table, "negative_inf").?;
    try testing.expect(std.math.isInf(neg_inf));
    try testing.expect(std.math.isNegativeInf(neg_inf));

    const exp_pos_inf = zontom.getFloat(&table, "explicit_positive_inf").?;
    try testing.expect(std.math.isPositiveInf(exp_pos_inf));

    const not_a_num = zontom.getFloat(&table, "not_a_number").?;
    try testing.expect(std.math.isNan(not_a_num));

    const pos_nan = zontom.getFloat(&table, "positive_nan").?;
    try testing.expect(std.math.isNan(pos_nan));

    const neg_nan = zontom.getFloat(&table, "negative_nan").?;
    try testing.expect(std.math.isNan(neg_nan));
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

test "offset datetime with UTC" {
    const source = "utc = 1979-05-27T07:32:00Z";
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const dt = zontom.getDatetime(&table, "utc");
    try testing.expect(dt != null);
    try testing.expectEqual(@as(i16, 0), dt.?.offset_minutes.?);
}

test "offset datetime with timezone" {
    const source =
        \\pst = 1979-05-27T00:32:00-07:00
        \\ist = 1979-05-27T00:32:00+05:30
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const pst = zontom.getDatetime(&table, "pst");
    try testing.expect(pst != null);
    try testing.expectEqual(@as(i16, -420), pst.?.offset_minutes.?); // -7 * 60

    const ist = zontom.getDatetime(&table, "ist");
    try testing.expect(ist != null);
    try testing.expectEqual(@as(i16, 330), ist.?.offset_minutes.?); // 5 * 60 + 30
}

test "datetime with fractional seconds" {
    const source =
        \\ms = 1979-05-27T00:32:00.999
        \\us = 1979-05-27T00:32:00.999999
        \\ns = 1979-05-27T00:32:00.999999999
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const ms = zontom.getDatetime(&table, "ms");
    try testing.expect(ms != null);
    try testing.expectEqual(@as(u32, 999000000), ms.?.nanosecond);

    const us = zontom.getDatetime(&table, "us");
    try testing.expect(us != null);
    try testing.expectEqual(@as(u32, 999999000), us.?.nanosecond);

    const ns = zontom.getDatetime(&table, "ns");
    try testing.expect(ns != null);
    try testing.expectEqual(@as(u32, 999999999), ns.?.nanosecond);
}

test "datetime with space delimiter" {
    const source = "dt = 1979-05-27 07:32:00";
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const dt = zontom.getDatetime(&table, "dt");
    try testing.expect(dt != null);
    try testing.expectEqual(@as(u8, 7), dt.?.hour);
}

test "local date only" {
    const source = "birthday = 1979-05-27";
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const val = table.get("birthday");
    try testing.expect(val != null);
    try testing.expect(val.? == .date);
    try testing.expectEqual(@as(u16, 1979), val.?.date.year);
    try testing.expectEqual(@as(u8, 5), val.?.date.month);
    try testing.expectEqual(@as(u8, 27), val.?.date.day);
}

test "local time only" {
    const source =
        \\morning = 07:32:00
        \\precise = 07:32:00.999999
    ;
    var table = try zontom.parse(testing.allocator, source);
    defer table.deinit();

    const morning = table.get("morning");
    try testing.expect(morning != null);
    try testing.expect(morning.? == .time);
    try testing.expectEqual(@as(u8, 7), morning.?.time.hour);
    try testing.expectEqual(@as(u8, 32), morning.?.time.minute);
    try testing.expectEqual(@as(u8, 0), morning.?.time.second);

    const precise = table.get("precise");
    try testing.expect(precise != null);
    try testing.expect(precise.? == .time);
    try testing.expectEqual(@as(u32, 999999000), precise.?.time.nanosecond);
}

test "datetime validation - invalid dates" {
    // Invalid month
    const bad_month = "date = 1979-13-01";
    const result1 = zontom.parse(testing.allocator, bad_month);
    try testing.expectError(error.InvalidValue, result1);

    // Invalid day
    const bad_day = "date = 1979-05-32";
    const result2 = zontom.parse(testing.allocator, bad_day);
    try testing.expectError(error.InvalidValue, result2);

    // Invalid hour
    const bad_hour = "dt = 1979-05-27T25:00:00";
    const result3 = zontom.parse(testing.allocator, bad_hour);
    try testing.expectError(error.InvalidValue, result3);
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
