const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const print = std.debug.print;

pub const CsvTokenType = enum {
    field, row_end, eof
};

pub const CsvToken = union(CsvTokenType) {
    field: []const u8, row_end: void, eof: void
};

pub const CsvError = error{ ShortBuffer, MisplacedQuote, NoSeparatorAfterField };

pub const CsvConfig = struct {
    colSeparator: u8 = ',', rowSeparator: u8 = '\n', initialBufferSize: usize = 1024
};

fn CsvReader(comptime Reader: type) type {

    // TODO comptime
    return struct {
        buffer: []u8 = undefined,
        current: []u8 = undefined,
        // pos: usize = 0,
        reader: Reader,
        all_read: bool = false,

        const Self = @This();

        pub fn init(reader: Reader, buffer: []u8) Self {
            return .{
                .buffer = buffer,
                .current = buffer[0..0],
                .reader = reader,
            };
        }

        inline fn empty(self: *Self) bool {
            return self.current.len == 0;
        }

        pub fn char(self: *Self) !?u8 {
            if (!try self.ensureData()) {
                return null;
            }

            const c = self.current[0];
            self.current = self.current[1..];

            return c;
        }

        pub fn peek(self: *Self) !?u8 {
            if (!try self.ensureData()) {
                return null;
            }

            return self.current[0];
        }

        pub fn until(self: *Self, terminators: []const u8) !?[]const u8 {
            if (!try self.ensureData()) {
                return null;
            }

            for (self.current) |c, pos| {
                // TODO inline
                for (terminators) |ct| {
                    // print("{c}=={}\n", .{ c, ct });
                    if (c == ct) {
                        const s = self.current[0..pos];
                        self.current = self.current[pos..];
                        print("{}|{}", .{ s, self.current });
                        return s;
                    }
                }
            }

            return null;
        }

        pub fn untilClosingQuote(self: *Self, quote: u8) !?[]const u8 {
            var idx: usize = 0;
            while (idx < self.current.len) : (idx += 1) {
                const c = self.current[idx];
                print("IDX QUOTED: {}={c}\n", .{ idx, c });
                if (c == quote) {
                    // double quotes, shift forward
                    // print("PEEK {c}\n", .{buffer[idx + 1]});
                    if (idx < self.current.len - 1 and self.current[idx + 1] == '"') {
                        print("DOUBLE QUOTES\n", .{});
                        idx += 1;
                    } else {
                        print("ALL_READ {}\n", .{self.all_read});
                        if (!self.all_read and idx == self.current.len - 1) {
                            return null;
                        }

                        const s = self.current[0..idx];
                        self.current = self.current[idx..];

                        return s;
                    }
                }
            }

            return null;
        }

        pub fn read(self: *Self) !bool {
            const current_len = self.current.len;
            if (current_len > 0) {
                mem.copy(u8, self.buffer, self.current);
            }

            const read_len = try self.reader.read(self.buffer[current_len..]);
            print("READ: current_len={} read_len={}\n", .{ current_len, read_len });
            self.current = self.buffer[0 .. current_len + read_len];
            self.all_read = read_len == 0;

            return self.current.len > 0;
        }

        pub inline fn ensureData(self: *Self) !bool {
            if (!self.empty()) {
                return true;
            }

            if (self.all_read) {
                return false;
            }

            return self.read();
        }
    };
}

/// Tokenizes input from reader into stream of CsvTokens
pub fn CsvTokenizer(comptime Reader: type) type {
    const Status = enum {
        Initial, RowStart, Field, QuotedFieldEnd, RowEnd, Eof, Finished
    };

    return struct {
        const Self = @This();

        config: CsvConfig,
        // terminalChars: [3]u8 = .{ 0, 0, '"' },

        reader: CsvReader(Reader),
        allocator: *Allocator,

        status: Status = .Initial,

        pub fn init(reader: Reader, allocator: *Allocator, config: CsvConfig) !Self {
            var buffer = try allocator.alloc(u8, config.initialBufferSize);

            // self.terminalChars[0] = config.colSeparator;
            // self.terminalChars[1] = config.rowSeparator;

            return Self{
                .config = config,
                .reader = CsvReader(Reader).init(reader, buffer),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: Self) void {
            self.allocator.free(self.reader.buffer);
        }

        pub fn next(self: *Self) !CsvToken {
            while (true) {
                print("STATUS: {}\n", .{self.status});
                switch (self.status) {
                    .Initial => {
                        const hasData = try self.reader.read();

                        self.status = if (hasData) .RowStart else .Eof;
                        continue;
                    },
                    .RowStart => {
                        if (!try self.reader.ensureData()) {
                            self.status = .Eof;
                            continue;
                        }

                        self.status = .Field;
                        continue;
                    },
                    .Field => {
                        if (!try self.reader.ensureData()) {
                            self.status = .RowEnd;
                            continue;
                        }

                        return try self.parseField();
                    },
                    .QuotedFieldEnd => {
                        // read closing quotes
                        _ = try self.reader.char();

                        if (!try self.reader.ensureData()) {
                            self.status = .RowEnd;
                            continue;
                        }

                        const c = (try self.reader.peek());

                        if (c) |value| {
                            if (value == self.config.colSeparator) {
                                _ = try self.reader.char();
                                self.status = .Field;
                                continue;
                            }

                            if (value == self.config.rowSeparator) {
                                self.status = .RowEnd;
                                continue;
                            }

                            // quote means that it did not fit into buffer and it cannot be analyzed as ""
                            if (value == '"') {
                                return CsvError.ShortBuffer;
                            }
                        } else {
                            self.status = .Eof;
                            continue;
                        }

                        return CsvError.NoSeparatorAfterField;
                    },
                    .RowEnd => {
                        if (!try self.reader.ensureData()) {
                            self.status = .Eof;
                            return CsvToken{ .row_end = {} };
                        }

                        _ = try self.reader.char();
                        self.status = .RowStart;

                        return CsvToken{ .row_end = {} };
                    },
                    .Eof => {
                        self.status = .Finished;
                        // TODO return null
                        return CsvToken{ .eof = {} };
                    },
                    .Finished => {},
                }
            }

            unreachable;
        }

        fn parseField(self: *Self) !CsvToken {
            const first = (try self.reader.peek()).?;

            if (first != '"') {
                // move terminal chars out
                // try to use const field
                var field = try self.reader.until(&[_]u8{ self.config.colSeparator, self.config.rowSeparator, '"' });
                if (field == null) {
                    // force read - maybe separator was not read yet
                    const hasData = try self.reader.read();
                    if (!hasData) {
                        return CsvError.ShortBuffer;
                    }

                    field = try self.reader.until(&[_]u8{ self.config.colSeparator, self.config.rowSeparator, '"' });
                    if (field == null) {
                        return CsvError.ShortBuffer;
                    }
                }

                const terminator = (try self.reader.peek()).?;

                print("TERMINATOR: {}\n", .{terminator});
                if (terminator == self.config.colSeparator) {
                    _ = try self.reader.char();
                    return CsvToken{ .field = field.? };
                }

                if (terminator == self.config.rowSeparator) {
                    self.status = .RowEnd;
                    return CsvToken{ .field = field.? };
                }

                if (terminator == '"') {
                    return CsvError.MisplacedQuote;
                }

                return CsvError.ShortBuffer;
            } else {
                // consume opening quote
                _ = try self.reader.char();
                var quotedField = try self.reader.untilClosingQuote('"');
                if (quotedField == null) {
                    print("QUOTED RETRY\n", .{});
                    // force read - maybe separator was not read yet
                    const hasData = try self.reader.read();
                    if (!hasData) {
                        return CsvError.ShortBuffer;
                    }

                    quotedField = try self.reader.untilClosingQuote('"');
                    if (quotedField == null) {
                        return CsvError.ShortBuffer;
                    }
                }

                self.status = .QuotedFieldEnd;
                return CsvToken{ .field = quotedField.? };
            }
        }
    };
}
