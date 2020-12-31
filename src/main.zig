const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;
const expect = testing.expect;
const print = std.debug.print;

const CsvResultType = enum {
    field, row, eof
};

const CsvResult = union(CsvResultType) {
    field: []u8, row: []u8, eof: void
};

const CsvError = error{ ShortBuffer, MisplacedQuote, NoDelimiterAfterField };

const CsvConfig = struct {
    colSeparator: u8 = ',', rowSeparator: u8 = '\n', initialBufferSize: usize = 1024
};

pub fn CsvIterator(comptime Reader: type) type {
    const Status = enum {
        Initial, ReadingField, Finished
    };

    return struct {
        const Self = @This();

        config: CsvConfig,

        reader: Reader,
        allocator: *Allocator,

        buffer: []u8 = undefined,
        current: []u8 = undefined,

        status: Status = .Initial,

        fn init(reader: Reader, allocator: *Allocator, config: CsvConfig) Self {
            return .{
                .config = config,
                .reader = reader,
                .allocator = allocator,
            };
        }

        fn deinit(self: Self) void {
            if (self.status == .ReadingField or self.status == .Finished) {
                self.allocator.free(self.buffer);
            }
        }

        fn next(self: *Self) !CsvResult {
            switch (self.status) {
                .Initial => {
                    self.buffer = try self.allocator.alloc(u8, self.config.initialBufferSize);
                    self.status = .ReadingField;
                    _ = try self.read();
                    return try self.parse();
                },
                .ReadingField => {
                    if (self.current.len == 0) {
                        self.status = .Finished;
                        return CsvResult{ .eof = {} };
                    }
                    return try self.parse();
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

        fn parse(self: *Self) CsvError!CsvResult {
            // print("PARSE {}\n", .{self});
            var idx: usize = 0;
            while (idx < self.current.len) : (idx += 1) {
                print("IDX: {}={c}\n", .{ idx, self.current[idx] });
                switch (self.current[idx]) {
                    ',' => { // self.colSeparator
                        const field = self.current[0..idx];
                        self.current = self.current[idx + 1 ..];

                        return CsvResult{ .field = field };
                    },
                    '\n' => { // self.rowSeparator
                        const field = self.current[0..idx];
                        self.current = self.current[idx + 1 ..];

                        return CsvResult{ .row = field };
                    },
                    '"' => {
                        if (idx != 0) {
                            return CsvError.MisplacedQuote;
                        }

                        const fieldEnd = try quotedFieldEnd(self, self.current[idx + 1 ..]);
                        const field = self.current[1 .. fieldEnd + 1];

                        const isEndOfBuffer = fieldEnd + 2 >= self.current.len;
                        const isRow = isEndOfBuffer or self.current[fieldEnd + 2] == '\n';

                        if (isRow) {
                            if (isEndOfBuffer) {
                                self.current = self.current[fieldEnd + 2 ..];
                            } else {
                                self.current = self.current[fieldEnd + 3 ..];
                            }

                            return CsvResult{ .row = field };
                        } else {
                            self.current = self.current[fieldEnd + 3 ..];
                            return CsvResult{ .field = field };
                        }
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
    const csv = &CsvIterator(std.fs.File.Reader).init(reader, testing.allocator, CsvConfig{});
    defer csv.deinit();
}

test "Read single simple record from file" {
    const file = try std.fs.cwd().openFile("test/test-1.csv", .{});
    defer file.close();
    const reader = file.reader();
    const csv = &CsvIterator(std.fs.File.Reader).init(reader, testing.allocator, CsvConfig{});
    defer csv.deinit();

    const field1 = try csv.next();
    expect(@as(CsvResultType, field1) == CsvResultType.field);
    expect(mem.eql(u8, field1.field, "1"));
    // print("FIELD: {}\n", .{fields[1]});

    const field2 = try csv.next();
    expect(@as(CsvResultType, field2) == CsvResultType.row);
    expect(mem.eql(u8, field2.row, "abc"));

    const end = try csv.next();
    expect(@as(CsvResultType, end) == CsvResultType.eof);
}

test "Read multiple simple records from file" {
    const file = try std.fs.cwd().openFile("test/test-2.csv", .{});
    defer file.close();
    const reader = file.reader();
    const csv = &CsvIterator(std.fs.File.Reader).init(reader, testing.allocator, CsvConfig{});
    defer csv.deinit();

    const field1 = try csv.next();
    expect(@as(CsvResultType, field1) == CsvResultType.field);
    expect(mem.eql(u8, field1.field, "1"));

    const field2 = try csv.next();
    expect(@as(CsvResultType, field2) == CsvResultType.row);
    expect(mem.eql(u8, field2.row, "abc"));

    const field3 = try csv.next();
    expect(@as(CsvResultType, field3) == CsvResultType.field);
    expect(mem.eql(u8, field3.field, "2"));

    const field4 = try csv.next();
    expect(@as(CsvResultType, field2) == CsvResultType.row);
    expect(mem.eql(u8, field4.row, "def ghc"));

    const end = try csv.next();
    expect(@as(CsvResultType, end) == CsvResultType.eof);
}

test "Read quoted fields" {
    const file = try std.fs.cwd().openFile("test/test-4.csv", .{});
    defer file.close();
    const reader = file.reader();
    const csv = &CsvIterator(std.fs.File.Reader).init(reader, testing.allocator, CsvConfig{});
    defer csv.deinit();

    const field1 = try csv.next();
    expect(@as(CsvResultType, field1) == CsvResultType.field);
    expect(mem.eql(u8, field1.field, "1"));

    const field2 = try csv.next();
    expect(@as(CsvResultType, field2) == CsvResultType.row);
    print("FIELD: {}\n", .{field2.row});
    expect(mem.eql(u8, field2.row, "def ghc"));

    const field3 = try csv.next();
    expect(@as(CsvResultType, field3) == CsvResultType.field);
    expect(mem.eql(u8, field3.field, "2"));

    const field4 = try csv.next();
    expect(@as(CsvResultType, field2) == CsvResultType.row);
    expect(mem.eql(u8, field4.row, "abc \"\"def\"\""));

    const end = try csv.next();
    expect(@as(CsvResultType, end) == CsvResultType.eof);
}

test "some field is longer than buffer" {
    const file = try std.fs.cwd().openFile("test/test-error-short-buffer.csv", .{});
    defer file.close();
    const reader = file.reader();
    const csv = &CsvIterator(std.fs.File.Reader).init(reader, testing.allocator, CsvConfig{ .initialBufferSize = 9 });
    defer csv.deinit();

    const field1 = csv.next();
    if (field1) {
        unreachable;
    } else |err| {
        expect(err == CsvError.ShortBuffer);
    }
}
