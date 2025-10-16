//! Fuzzing tests for security and robustness

const std = @import("std");
const zontom = @import("root.zig");

/// Test parsing random bytes doesn't crash
test "fuzz: random bytes" {
    const testing = std.testing;

    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    var i: usize = 0;
    while (i < 100) : (i += 1) {
        var buffer: [256]u8 = undefined;
        random.bytes(&buffer);

        // Should not crash, just might error
        var result = zontom.parseWithContext(testing.allocator, &buffer);
        result.deinit();
    }
}

/// Test parsing extremely long strings
test "fuzz: very long strings" {
    const testing = std.testing;

    const sizes = [_]usize{ 1000, 10_000, 100_000 };

    for (sizes) |size| {
        var buffer = try testing.allocator.alloc(u8, size + 20);
        defer testing.allocator.free(buffer);

        @memcpy(buffer[0..6], "name =");
        @memcpy(buffer[6..7], " ");
        @memcpy(buffer[7..8], "\"");
        @memset(buffer[8 .. 8 + size], 'a');
        @memcpy(buffer[8 + size .. 8 + size + 1], "\"");

        var result = zontom.parseWithContext(testing.allocator, buffer);
        defer result.deinit();

        if (result.table) |*table| {
            const name = zontom.getString(table, "name");
            if (name) |n| {
                try testing.expectEqual(size, n.len);
            }
        }
    }
}

/// Test deeply nested structures
test "fuzz: deep nesting" {
    const testing = std.testing;

    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    // Create deeply nested tables
    const depth = 50;
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        try buffer.appendSlice("[");
        var j: usize = 0;
        while (j <= i) : (j += 1) {
            if (j > 0) try buffer.appendSlice(".");
            try std.fmt.format(buffer.writer(), "level{d}", .{j});
        }
        try buffer.appendSlice("]\n");
        try std.fmt.format(buffer.writer(), "value = {d}\n\n", .{i});
    }

    var result = zontom.parseWithContext(testing.allocator, buffer.items);
    defer result.deinit();

    try testing.expect(result.table != null or result.error_context != null);
}

/// Test all ASCII characters in strings
test "fuzz: all ASCII characters" {
    const testing = std.testing;

    var buffer = std.ArrayList(u8).init(testing.allocator);
    defer buffer.deinit();

    try buffer.appendSlice("text = \"");

    var c: u8 = 32; // Start from space
    while (c < 127) : (c += 1) {
        switch (c) {
            '"', '\\' => {
                try buffer.append('\\');
                try buffer.append(c);
            },
            else => try buffer.append(c),
        }
    }

    try buffer.appendSlice("\"");

    var result = zontom.parseWithContext(testing.allocator, buffer.items);
    defer result.deinit();

    try testing.expect(result.table != null);
}

/// Test malformed TOML
test "fuzz: malformed inputs" {
    const testing = std.testing;

    const malformed = [_][]const u8{
        "[[[broken",
        "key = = value",
        "= value",
        "key value",
        "\"unclosed string",
        "[table\nmissing bracket",
        "123 = value",
        "true = false",
        "[[array]]\n[[array", // Unclosed array of tables
        "[a.b.\n]",           // Malformed dotted key
    };

    for (malformed) |input| {
        var result = zontom.parseWithContext(testing.allocator, input);
        defer result.deinit();

        // Should either parse or have error context, not crash
        try testing.expect(result.table != null or result.error_context != null);
    }
}

/// Test edge case numbers
test "fuzz: edge case numbers" {
    const testing = std.testing;

    const edge_cases = [_][]const u8{
        "num = 9223372036854775807",  // i64 max
        "num = -9223372036854775808", // i64 min
        "num = 0",
        "num = -0",
        "flt = 1.7976931348623157e308",    // Large float
        "flt = 2.2250738585072014e-308",   // Small float
        "flt = 0.0",
        "flt = -0.0",
    };

    for (edge_cases) |input| {
        var result = zontom.parseWithContext(testing.allocator, input);
        defer result.deinit();

        try testing.expect(result.table != null or result.error_context != null);
    }
}

/// Test empty and whitespace-only inputs
test "fuzz: empty inputs" {
    const testing = std.testing;

    const empty_inputs = [_][]const u8{
        "",
        " ",
        "\n",
        "\t",
        "   \n\n\t\t  \n",
        "# just a comment",
        "# comment 1\n# comment 2\n# comment 3",
    };

    for (empty_inputs) |input| {
        var result = zontom.parseWithContext(testing.allocator, input);
        defer result.deinit();

        // Empty/comment-only files should parse successfully
        if (result.table) |*table| {
            try testing.expectEqual(@as(usize, 0), table.map.count());
        }
    }
}

/// Test Unicode handling
test "fuzz: Unicode strings" {
    const testing = std.testing;

    const unicode_tests = [_][]const u8{
        "name = \"Hello 世界\"",
        "emoji = \"🦀🎉✨\"",
        "text = \"Здравствуй\"",
        "arabic = \"مرحبا\"",
    };

    for (unicode_tests) |input| {
        var result = zontom.parseWithContext(testing.allocator, input);
        defer result.deinit();

        try testing.expect(result.table != null);
    }
}
