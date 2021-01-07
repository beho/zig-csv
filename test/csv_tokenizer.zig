const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;
const expect = testing.expect;
usingnamespace @import("csv");

fn getTokenizer(file: std.fs.File, config: CsvConfig) !CsvTokenizer(std.fs.File.Reader) {
    const reader = file.reader();
    const csv = try CsvTokenizer(std.fs.File.Reader).init(reader, testing.allocator, config);
    return csv;
}

fn expectToken(comptime expected: CsvToken, actual: CsvToken) !void {
    if(@enumToInt(expected) != @enumToInt(actual)) {
        std.log.warn("Expected {} but is {}\n", .{expected, actual});
        return error.TestFailed;
    }

    switch(expected) {
        .field => {
            if(!std.mem.eql(u8, expected.field, actual.field)) {
                std.log.warn("Expected {} but is {}\n", .{expected, actual});
                return error.TestFailed;
            }
        },
        else => {}
    }
}

test "Create iterator for file reader" {
    const file = try std.fs.cwd().openFile("test/resources/test-1.csv", .{});
    defer file.close();
    const csv = try getTokenizer(file, .{});
    defer csv.deinit();
}

test "Read single simple record from file" {
    const file = try std.fs.cwd().openFile("test/resources/test-1.csv", .{});
    defer file.close();
    const csv = &try getTokenizer(file, .{});
    defer csv.deinit();

    try expectToken(CsvToken{.field = "1"}, try csv.next());
    try expectToken(CsvToken{.field = "abc"}, try csv.next());
    try expectToken(CsvToken{.row_end = {}}, try csv.next());

    try expectToken(CsvToken{.eof = {}}, try csv.next());
}

test "Read multiple simple records from file" {
    const file = try std.fs.cwd().openFile("test/resources/test-2.csv", .{});
    defer file.close();
    const csv = &try getTokenizer(file, .{});
    defer csv.deinit();

    try expectToken(CsvToken{.field = "1"}, try csv.next());
    try expectToken(CsvToken{.field = "abc"}, try csv.next());
    try expectToken(CsvToken{.row_end = {}}, try csv.next());

    try expectToken(CsvToken{.field = "2"}, try csv.next());
    try expectToken(CsvToken{.field = "def ghc"}, try csv.next());
    try expectToken(CsvToken{.row_end = {}}, try csv.next());

    try expectToken(CsvToken{.eof = {}}, try csv.next());
}

test "Read quoted fields" {
    const file = try std.fs.cwd().openFile("test/resources/test-4.csv", .{});
    defer file.close();
    const csv = &try getTokenizer(file, .{});
    defer csv.deinit();

    try expectToken(CsvToken{.field = "1"}, try csv.next());
    try expectToken(CsvToken{.field = "def ghc"}, try csv.next());
    try expectToken(CsvToken{.row_end = {}}, try csv.next());

    try expectToken(CsvToken{.field = "2"}, try csv.next());
    try expectToken(CsvToken{.field = "abc \"\"def\"\""}, try csv.next());
    try expectToken(CsvToken{.row_end = {}}, try csv.next());

    try expectToken(CsvToken{.eof = {}}, try csv.next());
}

test "Second read is necessary to obtain field" {
    const file = try std.fs.cwd().openFile("test/resources/test-read-required-for-field.csv", .{});
    defer file.close();
    const csv = &try getTokenizer(file, CsvConfig{ .initialBufferSize = 6 });
    defer csv.deinit();

    try expectToken(CsvToken{.field = "12345"}, try csv.next());
    try expectToken(CsvToken{.field = "67890"}, try csv.next());
    try expectToken(CsvToken{.row_end = {}}, try csv.next());

    try expectToken(CsvToken{.eof = {}}, try csv.next());
}

test "File is empty" {
    const file = try std.fs.cwd().openFile("test/resources/test-empty.csv", .{});
    defer file.close();
    const csv = &try getTokenizer(file, .{});
    defer csv.deinit();

    try expectToken(CsvToken{.eof = {}}, try csv.next());
}

test "Field is longer than buffer" {
    const file = try std.fs.cwd().openFile("test/resources/test-error-short-buffer.csv", .{});
    defer file.close();
    const csv = &try getTokenizer(file, CsvConfig{ .initialBufferSize = 9 });
    defer csv.deinit();

    const field1 = csv.next();
    if (field1) {
        unreachable;
    } else |err| {
        expect(err == CsvError.ShortBuffer);
    }
}

test "Quoted field is longer than buffer" {
    const file = try std.fs.cwd().openFile("test/resources/test-error-short-buffer-quoted.csv", .{});
    defer file.close();
    const csv = &try getTokenizer(file, CsvConfig{ .initialBufferSize = 10 });
    defer csv.deinit();

    const field1 = csv.next();
    if (field1) {
        unreachable;
    } else |err| {
        expect(err == CsvError.ShortBuffer);
    }
}

test "Quoted field with double quotes is longer than buffer" {
    const file = try std.fs.cwd().openFile("test/resources/test-error-short-buffer-quoted-with-double.csv", .{});
    defer file.close();
    const csv = &try getTokenizer(file, CsvConfig{ .initialBufferSize = 11 });
    defer csv.deinit();

    const field1 = csv.next();
    if (field1) {
        unreachable;
    } else |err| {
        expect(err == CsvError.ShortBuffer);
    }
}

test "Quoted field with double quotes can be read on retry" {
    const file = try std.fs.cwd().openFile("test/resources/test-error-short-buffer-quoted-with-double.csv", .{});
    defer file.close();
    const csv = &try getTokenizer(file, CsvConfig{ .initialBufferSize = 14 });
    defer csv.deinit();

    try expectToken(CsvToken{.field = "1234567890\"\""}, try csv.next());
    try expectToken(CsvToken{.row_end = {}}, try csv.next());

    try expectToken(CsvToken{.eof = {}}, try csv.next());
}

// TODO test last line with new line and without
