const std = @import("std");
const mem = std.mem;
const print = std.debug.print;
const assert = std.debug.assert;

pub const CsvTokenType = enum {
    field, row_end
};

pub const CsvToken = union(CsvTokenType) {
    field: []const u8, row_end: void
};

pub const CsvError = error{ ShortBuffer, MisplacedQuote, NoSeparatorAfterField };

pub const CsvConfig = struct {
    colSep: u8 = ',', rowSep: u8 = '\n', quote: u8 = '"'
};

fn CsvReader(comptime Reader: type) type {

    // TODO comptime
    return struct {
        buffer: []u8,
        current: []u8,

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

        pub inline fn peek(self: *Self) !?u8 {
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
                    if (c == ct) {
                        const s = self.current[0..pos];
                        self.current = self.current[pos..];
                        // print("{}|{}", .{ s, self.current });
                        return s;
                    }
                }
            }

            // print("ALL_READ: {}\n", .{self.all_read});
            return null;
        }

        pub fn untilClosingQuote(self: *Self, quote: u8) !?[]const u8 {
            if (!try self.ensureData()) {
                return null;
            }

            var idx: usize = 0;
            while (idx < self.current.len) : (idx += 1) {
                const c = self.current[idx];
                // print("IDX QUOTED: {}={c}\n", .{ idx, c });
                if (c == quote) {
                    // double quotes, shift forward
                    // print("PEEK {c}\n", .{buffer[idx + 1]});
                    if (idx < self.current.len - 1 and self.current[idx + 1] == '"') {
                        // print("DOUBLE QUOTES\n", .{});
                        idx += 1;
                    } else {
                        // print("ALL_READ {}\n", .{self.all_read});
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

        /// Tries to read more data from an underlying reader if buffer is not already full.
        /// If anything was read returns true, otherwise false.
        pub fn read(self: *Self) !bool {
            const current_len = self.current.len;

            if (current_len == self.buffer.len) {
                return false;
            }

            if (current_len > 0) {
                mem.copy(u8, self.buffer, self.current);
            }

            const read_len = try self.reader.read(self.buffer[current_len..]);
            // print("READ: current_len={} read_len={}\n", .{ current_len, read_len });

            self.current = self.buffer[0 .. current_len + read_len];
            self.all_read = read_len == 0;

            return read_len > 0;
        }

        // Ensures that there are some data in the buffer. Returns false if no data are available
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
        Initial, RowStart, Field, QuotedFieldEnd, RowEnd, Eof
    };

    return struct {
        const Self = @This();

        config: CsvConfig,
        terminalChars: [3]u8 = undefined,

        reader: CsvReader(Reader),

        status: Status = .Initial,

        pub fn init(reader: Reader, buffer: []u8, config: CsvConfig) !Self {
            return Self{
                .config = config,
                .terminalChars = [_]u8{ config.colSep, config.rowSep, '"' },
                .reader = CsvReader(Reader).init(reader, buffer),
            };
        }

        pub fn next(self: *Self) !?CsvToken {
            var nextStatus: ?Status = self.status;

            // Cannot use anonymous enum literals for Status
            // https://github.com/ziglang/zig/issues/4255

            while (nextStatus) |status| {
                // print("STATUS: {}\n", .{self.status});
                nextStatus = switch (status) {
                    .Initial => if (try self.reader.read()) Status.RowStart else Status.Eof,
                    .RowStart => if (!try self.reader.ensureData()) Status.Eof else Status.Field,
                    .Field => blk: {
                        if (!try self.reader.ensureData()) {
                            break :blk .RowEnd;
                        }

                        return try self.parseField();
                    },
                    .QuotedFieldEnd => blk: {
                        // read closing quotes
                        _ = try self.reader.char();

                        if (!try self.reader.ensureData()) {
                            break :blk Status.RowEnd;
                        }

                        const c = (try self.reader.peek());

                        if (c) |value| {
                            // print("END: {}\n", .{value});
                            if (value == self.config.colSep) {
                                // TODO write repro for assert with optional
                                // const colSep = try self.reader.char();
                                // assert(colSep == self.config.colSeparator);
                                const colSep = (try self.reader.char()).?;
                                assert(colSep == self.config.colSep);

                                break :blk Status.Field;
                            }

                            if (value == self.config.rowSep) {
                                break :blk Status.RowEnd;
                            }

                            // quote means that it did not fit into buffer and it cannot be analyzed as ""
                            // TODO use config
                            if (value == self.config.quote) {
                                return CsvError.ShortBuffer;
                            }
                        } else {
                            break :blk Status.Eof;
                        }

                        return CsvError.NoSeparatorAfterField;
                    },
                    .RowEnd => {
                        if (!try self.reader.ensureData()) {
                            self.status = .Eof;
                            return CsvToken{ .row_end = {} };
                        }

                        const rowSep = try self.reader.char();
                        assert(rowSep == self.config.rowSep);

                        self.status = .RowStart;

                        return CsvToken{ .row_end = {} };
                    },
                    .Eof => {
                        return null;
                    },
                };

                // make the transition and also ensure that nextStatus is set at this point
                self.status = nextStatus.?;
            }

            unreachable;
        }

        fn parseField(self: *Self) !CsvToken {
            const first = (try self.reader.peek()).?;

            if (first != '"') {
                var field = try self.reader.until(&self.terminalChars);
                if (field == null) {
                    // force read - maybe separator was not read yet
                    const hasData = try self.reader.read();
                    if (!hasData) {
                        return CsvError.ShortBuffer;
                    }

                    field = try self.reader.until(&self.terminalChars);
                    if (field == null) {
                        return CsvError.ShortBuffer;
                    }
                }

                const terminator = (try self.reader.peek()).?;

                if (terminator == self.config.colSep) {
                    _ = try self.reader.char();
                    return CsvToken{ .field = field.? };
                }

                if (terminator == self.config.rowSep) {
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
                    // force read - maybe separator was not read yet
                    const hasData = try self.reader.read();
                    if (!hasData) {
                        return CsvError.ShortBuffer;
                    }

                    // this read will fill the buffer
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
