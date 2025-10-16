//! Error reporting for ZonTOM parser
const std = @import("std");

pub const ParseError = error{
    UnexpectedToken,
    UnexpectedEof,
    DuplicateKey,
    InvalidValue,
    InvalidTable,
    InvalidArray,
    OutOfMemory,
};

pub const ErrorContext = struct {
    line: usize,
    column: usize,
    source_line: []const u8,
    message: []const u8,
    suggestion: ?[]const u8 = null,

    pub fn format(
        self: ErrorContext,
        writer: anytype,
    ) !void {
        try writer.print("Error at line {d}, column {d}:\n", .{ self.line, self.column });
        try writer.print("  {s}\n", .{self.source_line});

        // Print a caret pointing to the error column
        try writer.writeByteNTimes(' ', 2 + self.column - 1);
        try writer.writeAll("^\n");

        try writer.print("  {s}\n", .{self.message});

        if (self.suggestion) |hint| {
            try writer.print("  Hint: {s}\n", .{hint});
        }
    }
};

/// Extract the source line for error reporting
pub fn getSourceLine(source: []const u8, line_number: usize) []const u8 {
    var current_line: usize = 1;
    var line_start: usize = 0;

    for (source, 0..) |c, i| {
        if (current_line == line_number) {
            if (c == '\n') {
                return source[line_start..i];
            }
        } else if (c == '\n') {
            current_line += 1;
            line_start = i + 1;
        }
    }

    // If we reached the end without finding a newline
    if (current_line == line_number) {
        return source[line_start..];
    }

    return "";
}

test "getSourceLine basic" {
    const testing = std.testing;

    const source = "line 1\nline 2\nline 3";

    const line1 = getSourceLine(source, 1);
    try testing.expectEqualStrings("line 1", line1);

    const line2 = getSourceLine(source, 2);
    try testing.expectEqualStrings("line 2", line2);

    const line3 = getSourceLine(source, 3);
    try testing.expectEqualStrings("line 3", line3);
}

test "getSourceLine single line" {
    const testing = std.testing;

    const source = "single line";
    const line = getSourceLine(source, 1);
    try testing.expectEqualStrings("single line", line);
}
