//  Copyright (c) 2021 beho
//
//  This library is free software; you can redistribute it and/or modify it
//  under the terms of the MIT license. See LICENSE for details.

const std = @import("std");
const testing = std.testing;
const expect = testing.expect;
const csv_mod = @import("csv");

var default_buffer = [_]u8{0} ** 1024;

fn getTokenizer(file: std.fs.File, buffer: []u8, config: csv_mod.CsvConfig) !csv_mod.CsvTokenizer(std.fs.File.Reader) {
    const reader = file.reader();
    const csv = try csv_mod.CsvTokenizer(std.fs.File.Reader).init(reader, buffer, config);
    return csv;
}

fn expectToken(comptime expected: csv_mod.CsvToken, maybe_actual: ?csv_mod.CsvToken) !void {
    if (maybe_actual) |actual| {
        if (@intFromEnum(expected) != @intFromEnum(actual)) {
            std.log.warn("Expected {?} but is {?}\n", .{ expected, actual });
            return error.TestFailed;
        }

        switch (expected) {
            .field => {
                try testing.expectEqualStrings(expected.field, actual.field);
            },
            else => {},
        }
    } else {
        std.log.warn("Expected {?} but is {?}\n", .{ expected, maybe_actual });
        return error.TestFailed;
    }
}

test "Create iterator for file reader" {
    const file = try std.fs.cwd().openFile("test/resources/test-1.csv", .{});
    defer file.close();

    _ = try getTokenizer(file, &default_buffer, .{});
}

test "Read single simple record from file" {
    const file = try std.fs.cwd().openFile("test/resources/test-1.csv", .{});
    defer file.close();
    var csv = try getTokenizer(file, &default_buffer, .{});

    try expectToken(csv_mod.CsvToken{ .field = "1" }, try csv.next());
    try expectToken(csv_mod.CsvToken{ .field = "abc" }, try csv.next());
    try expectToken(csv_mod.CsvToken{ .row_end = {} }, try csv.next());

    const next = csv.next() catch unreachable;

    try expect(next == null);
}

test "Read multiple simple records from file" {
    const file = try std.fs.cwd().openFile("test/resources/test-2.csv", .{});
    defer file.close();
    var csv = try getTokenizer(file, &default_buffer, .{});

    try expectToken(csv_mod.CsvToken{ .field = "1" }, try csv.next());
    try expectToken(csv_mod.CsvToken{ .field = "abc" }, try csv.next());
    try expectToken(csv_mod.CsvToken{ .row_end = {} }, try csv.next());

    try expectToken(csv_mod.CsvToken{ .field = "2" }, try csv.next());
    try expectToken(csv_mod.CsvToken{ .field = "def ghc" }, try csv.next());
    try expectToken(csv_mod.CsvToken{ .row_end = {} }, try csv.next());

    const next = csv.next() catch unreachable;

    try expect(next == null);
}

test "Read quoted fields" {
    const file = try std.fs.cwd().openFile("test/resources/test-4.csv", .{});
    defer file.close();
    var csv = try getTokenizer(file, &default_buffer, .{});

    try expectToken(csv_mod.CsvToken{ .field = "1" }, try csv.next());
    try expectToken(csv_mod.CsvToken{ .field = "def ghc" }, try csv.next());
    try expectToken(csv_mod.CsvToken{ .row_end = {} }, try csv.next());

    try expectToken(csv_mod.CsvToken{ .field = "2" }, try csv.next());
    try expectToken(csv_mod.CsvToken{ .field = "abc \"def\"" }, try csv.next());
    try expectToken(csv_mod.CsvToken{ .row_end = {} }, try csv.next());

    const next = csv.next() catch unreachable;

    try expect(next == null);
}

test "Second read is necessary to obtain field" {
    const file = try std.fs.cwd().openFile("test/resources/test-read-required-for-field.csv", .{});
    defer file.close();
    var csv = try getTokenizer(file, default_buffer[0..6], .{});

    try expectToken(csv_mod.CsvToken{ .field = "12345" }, try csv.next());
    try expectToken(csv_mod.CsvToken{ .field = "67890" }, try csv.next());
    try expectToken(csv_mod.CsvToken{ .row_end = {} }, try csv.next());

    const next = csv.next() catch unreachable;

    try expect(next == null);
}

test "File is empty" {
    const file = try std.fs.cwd().openFile("test/resources/test-empty.csv", .{});
    defer file.close();
    var csv = try getTokenizer(file, &default_buffer, .{});

    const next = csv.next() catch unreachable;

    try expect(next == null);
}

test "Field is longer than buffer" {
    const file = try std.fs.cwd().openFile("test/resources/test-error-short-buffer.csv", .{});
    defer file.close();
    var csv = try getTokenizer(file, default_buffer[0..9], .{});

    const next = csv.next();
    try std.testing.expectError(csv_mod.CsvError.ShortBuffer, next);
}

test "Quoted field is longer than buffer" {
    const file = try std.fs.cwd().openFile("test/resources/test-error-short-buffer-quoted.csv", .{});
    defer file.close();
    var csv = try getTokenizer(file, default_buffer[0..10], .{});

    const next = csv.next();
    try std.testing.expectError(csv_mod.CsvError.ShortBuffer, next);
}

test "Quoted field with double quotes is longer than buffer" {
    const file = try std.fs.cwd().openFile("test/resources/test-error-short-buffer-quoted-with-double.csv", .{});
    defer file.close();
    var csv = try getTokenizer(file, default_buffer[0..11], .{});

    const next = csv.next();
    try std.testing.expectError(csv_mod.CsvError.ShortBuffer, next);
}

test "Quoted field with double quotes can be read on retry" {
    const file = try std.fs.cwd().openFile("test/resources/test-error-short-buffer-quoted-with-double.csv", .{});
    defer file.close();
    var csv = try getTokenizer(file, default_buffer[0..14], .{});

    try expectToken(csv_mod.CsvToken{ .field = "1234567890\"" }, try csv.next());
    try expectToken(csv_mod.CsvToken{ .row_end = {} }, try csv.next());

    const next = csv.next() catch unreachable;

    try expect(next == null);
}

// TODO test last line with new line and without
