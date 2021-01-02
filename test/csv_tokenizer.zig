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

    const field1 = try csv.next();
    expect(@as(CsvTokenType, field1) == CsvTokenType.field);
    expect(mem.eql(u8, field1.field, "1"));
    // print("FIELD: {}\n", .{fields[1]});

    const field2 = try csv.next();
    expect(@as(CsvTokenType, field2) == CsvTokenType.field);
    expect(mem.eql(u8, field2.field, "abc"));

    const row1 = try csv.next();
    expect(@as(CsvTokenType, row1) == CsvTokenType.row_end);

    const end = try csv.next();
    expect(@as(CsvTokenType, end) == CsvTokenType.eof);
}

test "Read multiple simple records from file" {
    const file = try std.fs.cwd().openFile("test/resources/test-2.csv", .{});
    defer file.close();
    const csv = &try getTokenizer(file, .{});
    defer csv.deinit();

    const field1 = try csv.next();
    expect(@as(CsvTokenType, field1) == CsvTokenType.field);
    expect(mem.eql(u8, field1.field, "1"));

    const field2 = try csv.next();
    expect(@as(CsvTokenType, field2) == CsvTokenType.field);
    expect(mem.eql(u8, field2.field, "abc"));

    const row1 = try csv.next();
    expect(@as(CsvTokenType, row1) == CsvTokenType.row_end);

    const field3 = try csv.next();
    expect(@as(CsvTokenType, field3) == CsvTokenType.field);
    expect(mem.eql(u8, field3.field, "2"));

    const field4 = try csv.next();
    expect(@as(CsvTokenType, field2) == CsvTokenType.field);
    expect(mem.eql(u8, field4.field, "def ghc"));

    const row2 = try csv.next();
    expect(@as(CsvTokenType, row2) == CsvTokenType.row_end);

    const end = try csv.next();
    expect(@as(CsvTokenType, end) == CsvTokenType.eof);
}

test "Read quoted fields" {
    const file = try std.fs.cwd().openFile("test/resources/test-4.csv", .{});
    defer file.close();
    const csv = &try getTokenizer(file, .{});
    defer csv.deinit();

    const field1 = try csv.next();
    expect(@as(CsvTokenType, field1) == CsvTokenType.field);
    expect(mem.eql(u8, field1.field, "1"));

    const field2 = try csv.next();
    expect(@as(CsvTokenType, field2) == CsvTokenType.field);
    expect(mem.eql(u8, field2.field, "def ghc"));

    const row1 = try csv.next();
    expect(@as(CsvTokenType, row1) == CsvTokenType.row_end);

    const field3 = try csv.next();
    expect(@as(CsvTokenType, field3) == CsvTokenType.field);
    expect(mem.eql(u8, field3.field, "2"));

    const field4 = try csv.next();
    expect(@as(CsvTokenType, field2) == CsvTokenType.field);
    expect(mem.eql(u8, field4.field, "abc \"\"def\"\""));

    const row2 = try csv.next();
    expect(@as(CsvTokenType, row2) == CsvTokenType.row_end);

    const end = try csv.next();
    expect(@as(CsvTokenType, end) == CsvTokenType.eof);
}

test "File is empty" {
    const file = try std.fs.cwd().openFile("test/resources/test-empty.csv", .{});
    defer file.close();
    const csv = &try getTokenizer(file, .{});
    defer csv.deinit();

    const end = try csv.next();
    expect(@as(CsvTokenType, end) == CsvTokenType.eof);
}

test "some field is longer than buffer" {
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

// TODO test last line with new line and without
