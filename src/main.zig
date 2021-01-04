const std = @import("std");
const Allocator = std.mem.Allocator;
const print = std.debug.print;

pub const CsvTokenType = enum {
    field, row_end, eof
};

pub const CsvToken = union(CsvTokenType) {
    field: []u8, row_end: void, eof: void
};

pub const CsvError = error{ ShortBuffer, MisplacedQuote, NoDelimiterAfterField };

pub const CsvConfig = struct {
    colSeparator: u8 = ',', rowSeparator: u8 = '\n', initialBufferSize: usize = 1024
};

/// Tokenizes input from reader into stream of CsvTokens
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

        pub fn init(reader: Reader, allocator: *Allocator, config: CsvConfig) !Self {
            var buffer = try allocator.alloc(u8, config.initialBufferSize);
            return Self{
                .config = config,
                .reader = reader,
                .allocator = allocator,
                .buffer = buffer,
            };
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.buffer);
        }

        pub fn next(self: *Self) !CsvToken {
            while (true) {
                print("STATUS: {}\n", .{self.status});
                switch (self.status) {
                    .Initial => {
                        const hasData = try self.read();

                        self.status = if (hasData) .RowStart else .Eof;
                        continue;
                    },
                    .RowStart => {
                        if (self.current.len == 0) {
                            const hasData = try self.read();

                            if (!hasData) {
                                self.status = .Eof;
                                continue;
                            }
                        }

                        self.status = .Field;
                        continue;
                    },
                    .Field => {
                        if (self.current.len == 0) {
                            const hasData = try self.read();

                            if (!hasData) {
                                self.status = .RowEnd;
                                continue;
                            }
                        }

                        return try self.parseField();
                    },
                    .QuotedFieldEnd => {
                        self.current = self.current[1..];

                        if (self.current.len == 0) {
                            const hasData = try self.read();

                            if (!hasData) {
                                self.status = .RowEnd;
                                continue;
                            }
                        }

                        print("QuotedFieldEnd: {c}\n", .{self.current[0]});
                        switch (self.current[0]) {
                            '\n' => {
                                self.status = .RowEnd;
                                continue;
                            },
                            ',' => {
                                self.current = self.current[1..];
                                self.status = .Field;
                                continue;
                            },
                            else => unreachable,
                        }
                    },
                    .RowEnd => {
                        if (self.current.len == 0) {
                            const hasData = try self.read();

                            if (!hasData) {
                                self.status = .Eof;
                                return CsvToken{ .row_end = {} };
                            }
                        }

                        self.current = self.current[1..];
                        self.status = .RowStart;

                        return CsvToken{ .row_end = {} };
                    },
                    .Eof => {
                        self.status = .Finished;
                        return CsvToken{ .eof = {} };
                    },
                    .Finished => {},
                }
            }

            unreachable;
        }

        fn read(self: *Self) !bool {
            const len = try self.reader.read(self.buffer);
            self.current = self.buffer[0..len];

            return len > 0;
        }

        fn parseField(self: *Self) CsvError!CsvToken {
            // print("PARSE {}\n", .{self});
            var idx: usize = 0;
            while (idx < self.current.len) : (idx += 1) {
                print("current[{}]={c}\n", .{ idx, self.current[idx] });
                switch (self.current[idx]) {
                    ',' => { // self.colSeparator
                        const field = self.current[0..idx];
                        self.current = self.current[idx + 1 ..];

                        return CsvToken{ .field = field };
                    },
                    '\n' => { // self.rowSeparator
                        const field = self.current[0..idx];
                        self.current = self.current[idx..];
                        self.status = .RowEnd;

                        return CsvToken{ .field = field };
                    },
                    '"' => {
                        if (idx != 0) {
                            return CsvError.MisplacedQuote;
                        }

                        const fieldEnd = 1 + try quotedFieldEnd(self, self.current[1..]);
                        const field = self.current[1..fieldEnd];

                        self.current = self.current[fieldEnd..];
                        self.status = .QuotedFieldEnd;

                        return CsvToken{ .field = field };
                    },
                    else => {},
                }
            }

            // field cannot fit into buffer
            if (self.current.len == self.buffer.len) {
                return CsvError.ShortBuffer;
            }

            // TODO read and try again
            unreachable;
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
