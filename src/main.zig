const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;
const expect = testing.expect;
const print = std.debug.print;

const CsvResultType = enum {
    field, row_end, eof
};

const CsvResult = union(CsvResultType) {
    field: []u8, row_end: void, eof: void
};

const CsvError = error{ ShortBuffer, MisplacedQuote, NoDelimiterAfterField };

const CsvConfig = struct {
    colSeparator: u8 = ',', rowSeparator: u8 = '\n', initialBufferSize: usize = 1024
};

pub fn CsvTokenizer(comptime Reader: type) type {
    const Status = enum {
        Initial, RowStart, Field, QuotedFieldEnd, RowEnd, Eof, Finished
    };

    return struct {
        const Self = @This();

        config: CsvConfig,

        reader: Reader,
        allocator: *Allocator,

        buffer: []u8 = undefined,
        current: []u8 = undefined,

        status: Status = .Initial,

        fn init(reader: Reader, allocator: *Allocator, config: CsvConfig) !Self {
            var buffer = try allocator.alloc(u8, config.initialBufferSize);
            return Self{
                .config = config,
                .reader = reader,
                .allocator = allocator,
                .buffer = buffer,
            };
        }

        fn deinit(self: Self) void {
            self.allocator.free(self.buffer);
        }

        fn next(self: *Self) !CsvResult {
            print("STATUS: {}\n", .{self.status});
            switch (self.status) {
                .Initial => {
                    _ = try self.read();
                    self.status = .RowStart;
                    return self.next();
                },
                .RowStart => {
                    if (self.current.len == 0) {
                        self.status = .Eof;
                        return CsvResult{ .eof = {} };
                    }

                    self.status = .Field;
                    return self.next();
                },
                .Field => {
                    if (self.current.len == 0) {
                        self.status = .RowEnd;
                        return self.next();
                    }

                    return try self.parseField();
                },
                .QuotedFieldEnd => {
                    self.current = self.current[1..];

                    if (self.current.len == 0) {
                        self.status = .RowEnd;
                        return self.next();
                    }

                    print("QuotedFieldEnd: {c}\n", .{self.current[0]});
                    switch (self.current[0]) {
                        '\n' => {
                            self.status = .RowEnd;
                        },
                        ',' => {
                            self.current = self.current[1..];
                            self.status = .Field;
                        },
                        else => unreachable,
                    }

                    return self.next();
                },
                .RowEnd => {
                    if (self.current.len == 0) {
                        self.status = .Eof;
                        return CsvResult{ .row_end = {} };
                    }

                    self.current = self.current[1..];
                    self.status = .RowStart;

                    return CsvResult{ .row_end = {} };
                },
                .Eof => {
                    self.status = .Finished;
                    return CsvResult{ .eof = {} };
                },
                .Finished => {},
            }

            unreachable;
        }

        fn read(self: *Self) !void {
            const len = try self.reader.read(self.buffer);
            // TODO handle len == 0

            self.current = self.buffer[0..len];
        }

        fn parseField(self: *Self) CsvError!CsvResult {
            // print("PARSE {}\n", .{self});
            var idx: usize = 0;
            while (idx < self.current.len) : (idx += 1) {
                print("current[{}]={c}\n", .{ idx, self.current[idx] });
                switch (self.current[idx]) {
                    ',' => { // self.colSeparator
                        const field = self.current[0..idx];
                        self.current = self.current[idx + 1 ..];

                        return CsvResult{ .field = field };
                    },
                    '\n' => { // self.rowSeparator
                        const field = self.current[0..idx];
                        self.current = self.current[idx..];
                        self.status = .RowEnd;

                        return CsvResult{ .field = field };
                    },
                    '"' => {
                        if (idx != 0) {
                            return CsvError.MisplacedQuote;
                        }

                        const fieldEnd = 1 + try quotedFieldEnd(self, self.current[1..]);
                        const field = self.current[1..fieldEnd];

                        self.current = self.current[fieldEnd..];
                        self.status = .QuotedFieldEnd;

                        return CsvResult{ .field = field };
                    },
                    else => {},
                }
            }

            return CsvError.ShortBuffer;
        }

        fn quotedFieldEnd(self: *Self, buffer: []u8) CsvError!usize {
            var idx: usize = 0;
            while (idx < buffer.len) : (idx += 1) {
                print("IDX QUOTED: {}={c}\n", .{ idx, buffer[idx] });
                switch (buffer[idx]) {
                    '"' => {
                        // double quotes, shift forward
                        // print("PEEK {c}\n", .{buffer[idx + 1]});
                        if (idx < buffer.len - 1 and buffer[idx + 1] == '"') {
                            print("DOUBLE QUOTES\n", .{});
                            idx += 1;
                        } else {
                            return idx;
                        }
                    },
                    else => {},
                }
            }

            return CsvError.ShortBuffer;
        }
    };
}

test "Create iterator for file reader" {
    const file = try std.fs.cwd().openFile("test/test-1.csv", .{});
    defer file.close();
    const reader = file.reader();
    const csv = &(try CsvTokenizer(std.fs.File.Reader).init(reader, testing.allocator, CsvConfig{}));
    defer csv.deinit();
}

test "Read single simple record from file" {
    const file = try std.fs.cwd().openFile("test/test-1.csv", .{});
    defer file.close();
    const reader = file.reader();
    const csv = &(try CsvTokenizer(std.fs.File.Reader).init(reader, testing.allocator, CsvConfig{}));
    defer csv.deinit();

    const field1 = try csv.next();
    expect(@as(CsvResultType, field1) == CsvResultType.field);
    expect(mem.eql(u8, field1.field, "1"));
    // print("FIELD: {}\n", .{fields[1]});

    const field2 = try csv.next();
    expect(@as(CsvResultType, field2) == CsvResultType.field);
    expect(mem.eql(u8, field2.field, "abc"));

    const row1 = try csv.next();
    expect(@as(CsvResultType, row1) == CsvResultType.row_end);

    const end = try csv.next();
    expect(@as(CsvResultType, end) == CsvResultType.eof);
}

test "Read multiple simple records from file" {
    const file = try std.fs.cwd().openFile("test/test-2.csv", .{});
    defer file.close();
    const reader = file.reader();
    const csv = &(try CsvTokenizer(std.fs.File.Reader).init(reader, testing.allocator, CsvConfig{}));
    defer csv.deinit();

    const field1 = try csv.next();
    expect(@as(CsvResultType, field1) == CsvResultType.field);
    expect(mem.eql(u8, field1.field, "1"));

    const field2 = try csv.next();
    expect(@as(CsvResultType, field2) == CsvResultType.field);
    expect(mem.eql(u8, field2.field, "abc"));

    const row1 = try csv.next();
    expect(@as(CsvResultType, row1) == CsvResultType.row_end);

    const field3 = try csv.next();
    expect(@as(CsvResultType, field3) == CsvResultType.field);
    expect(mem.eql(u8, field3.field, "2"));

    const field4 = try csv.next();
    expect(@as(CsvResultType, field2) == CsvResultType.field);
    expect(mem.eql(u8, field4.field, "def ghc"));

    const row2 = try csv.next();
    expect(@as(CsvResultType, row2) == CsvResultType.row_end);

    const end = try csv.next();
    expect(@as(CsvResultType, end) == CsvResultType.eof);
}

test "Read quoted fields" {
    const file = try std.fs.cwd().openFile("test/test-4.csv", .{});
    defer file.close();
    const reader = file.reader();
    const csv = &(try CsvTokenizer(std.fs.File.Reader).init(reader, testing.allocator, CsvConfig{}));
    defer csv.deinit();

    const field1 = try csv.next();
    expect(@as(CsvResultType, field1) == CsvResultType.field);
    expect(mem.eql(u8, field1.field, "1"));

    const field2 = try csv.next();
    expect(@as(CsvResultType, field2) == CsvResultType.field);
    expect(mem.eql(u8, field2.field, "def ghc"));

    const row1 = try csv.next();
    expect(@as(CsvResultType, row1) == CsvResultType.row_end);

    const field3 = try csv.next();
    expect(@as(CsvResultType, field3) == CsvResultType.field);
    expect(mem.eql(u8, field3.field, "2"));

    const field4 = try csv.next();
    expect(@as(CsvResultType, field2) == CsvResultType.field);
    expect(mem.eql(u8, field4.field, "abc \"\"def\"\""));

    const row2 = try csv.next();
    expect(@as(CsvResultType, row2) == CsvResultType.row_end);

    const end = try csv.next();
    expect(@as(CsvResultType, end) == CsvResultType.eof);
}

test "some field is longer than buffer" {
    const file = try std.fs.cwd().openFile("test/test-error-short-buffer.csv", .{});
    defer file.close();
    const reader = file.reader();
    const csv = &(try CsvTokenizer(std.fs.File.Reader).init(reader, testing.allocator, CsvConfig{ .initialBufferSize = 9 }));
    defer csv.deinit();

    const field1 = csv.next();
    if (field1) {
        unreachable;
    } else |err| {
        expect(err == CsvError.ShortBuffer);
    }
}

// TODO test last line with new line and without
