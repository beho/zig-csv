//  Copyright (c) 2021 beho
//
//  This library is free software; you can redistribute it and/or modify it
//  under the terms of the MIT license. See LICENSE for details.

const std = @import("std");
const mem = std.mem;
const print = std.debug.print;
const assert = std.debug.assert;

pub const CsvTokenType = enum {
    field,
    row_end,
};

pub const CsvToken = union(CsvTokenType) {
    field: []const u8,
    row_end: void,
};

pub const CsvError = error{
    ShortBuffer,
    MisplacedQuote,
    NoSeparatorAfterField,
};

pub const CsvConfig = struct {
    col_sep: u8 = ',',
    row_sep: u8 = '\n',
    quote: u8 = '"',
};

const QuoteFieldReadResult = struct {
    value: []u8,
    contains_quotes: bool,
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

        pub fn until(self: *Self, terminators: []const u8) !?[]u8 {
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

        pub fn untilClosingQuote(self: *Self, quote: u8) !?QuoteFieldReadResult {
            if (!try self.ensureData()) {
                return null;
            }

            var idx: usize = 0;
            var contains_quotes: bool = false;
            while (idx < self.current.len) : (idx += 1) {
                const c = self.current[idx];
                // print("IDX QUOTED: {}={c}\n", .{ idx, c });
                if (c == quote) {
                    // double quotes, shift forward
                    // print("PEEK {c}\n", .{buffer[idx + 1]});
                    if (idx < self.current.len - 1 and self.current[idx + 1] == '"') {
                        // print("DOUBLE QUOTES\n", .{});
                        contains_quotes = true;
                        idx += 1;
                    } else {
                        // print("ALL_READ {}\n", .{self.all_read});
                        if (!self.all_read and idx == self.current.len - 1) {
                            return null;
                        }

                        const s = self.current[0..idx];
                        self.current = self.current[idx..];

                        return QuoteFieldReadResult{ .value = s, .contains_quotes = contains_quotes };
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
        initial,
        row_start,
        field,
        quoted_field_end,
        row_end,
        eof,
    };

    return struct {
        const Self = @This();

        config: CsvConfig,
        terminal_chars: [3]u8 = undefined,

        reader: CsvReader(Reader),

        status: Status = .initial,

        pub fn init(reader: Reader, buffer: []u8, config: CsvConfig) !Self {
            return Self{
                .config = config,
                .terminal_chars = [_]u8{ config.col_sep, config.row_sep, '"' },
                .reader = CsvReader(Reader).init(reader, buffer),
            };
        }

        pub fn next(self: *Self) !?CsvToken {
            var next_status: ?Status = self.status;

            // Cannot use anonymous enum literals for Status
            // https://github.com/ziglang/zig/issues/4255

            while (next_status) |status| {
                // print("STATUS: {}\n", .{self.status});
                next_status = switch (status) {
                    .initial => if (try self.reader.read()) Status.row_start else Status.eof,
                    .row_start => if (!try self.reader.ensureData()) Status.eof else Status.field,
                    .field => blk: {
                        if (!try self.reader.ensureData()) {
                            break :blk .row_end;
                        }

                        return try self.parseField();
                    },
                    .quoted_field_end => blk: {
                        // read closing quotes
                        const quote = try self.reader.char();
                        assert(quote == self.config.quote);

                        if (!try self.reader.ensureData()) {
                            break :blk Status.row_end;
                        }

                        const c = (try self.reader.peek());

                        if (c) |value| {
                            // print("END: {}\n", .{value});
                            if (value == self.config.col_sep) {
                                // TODO write repro for assert with optional
                                // const col_sep = try self.reader.char();
                                // assert(col_sep == self.config.col_sep);
                                const col_sep = (try self.reader.char()).?;
                                assert(col_sep == self.config.col_sep);

                                break :blk Status.field;
                            }

                            if (value == self.config.row_sep) {
                                break :blk Status.row_end;
                            }

                            // quote means that it did not fit into buffer and it cannot be analyzed as ""
                            if (value == self.config.quote) {
                                return CsvError.ShortBuffer;
                            }
                        } else {
                            break :blk Status.eof;
                        }

                        return CsvError.NoSeparatorAfterField;
                    },
                    .row_end => {
                        if (!try self.reader.ensureData()) {
                            self.status = Status.eof;
                            return CsvToken{ .row_end = {} };
                        }

                        const rowSep = try self.reader.char();
                        assert(rowSep == self.config.row_sep);

                        self.status = Status.row_start;

                        return CsvToken{ .row_end = {} };
                    },
                    .eof => {
                        return null;
                    },
                };

                // make the transition and also ensure that next_status is set at this point
                self.status = next_status.?;
            }

            unreachable;
        }

        fn parseField(self: *Self) !CsvToken {
            const first = (try self.reader.peek()).?;

            if (first != '"') {
                var field = try self.reader.until(&self.terminal_chars);
                if (field == null) {
                    // force read - maybe separator was not read yet
                    const hasData = try self.reader.read();
                    if (!hasData) {
                        return CsvError.ShortBuffer;
                    }

                    field = try self.reader.until(&self.terminal_chars);
                    if (field == null) {
                        return CsvError.ShortBuffer;
                    }
                }

                const terminator = (try self.reader.peek()).?;

                if (terminator == self.config.col_sep) {
                    _ = try self.reader.char();
                    return CsvToken{ .field = field.? };
                }

                if (terminator == self.config.row_sep) {
                    self.status = .row_end;
                    return CsvToken{ .field = field.? };
                }

                if (terminator == self.config.quote) {
                    return CsvError.MisplacedQuote;
                }

                return CsvError.ShortBuffer;
            } else {
                // consume opening quote
                _ = try self.reader.char();
                var quoted_field = try self.reader.untilClosingQuote(self.config.quote);
                if (quoted_field == null) {
                    // force read - maybe separator was not read yet
                    const hasData = try self.reader.read();
                    if (!hasData) {
                        return CsvError.ShortBuffer;
                    }

                    // this read will fill the buffer
                    quoted_field = try self.reader.untilClosingQuote(self.config.quote);
                    if (quoted_field == null) {
                        return CsvError.ShortBuffer;
                    }
                }

                self.status = .quoted_field_end;

                const field = quoted_field.?;
                if (!field.contains_quotes) {
                    return CsvToken{ .field = field.value };
                } else {
                    // walk the field and remove double quotes by shifting bytes
                    const value = field.value;
                    var diff: u64 = 0;
                    var idx: usize = 0;
                    while (idx < value.len) : (idx += 1) {
                        const c = value[idx];
                        value[idx - diff] = c;

                        if (c == self.config.quote) {
                            diff += 1;
                            idx += 1;
                        }
                    }

                    return CsvToken{ .field = value[0 .. value.len - diff] };
                }
            }
        }
    };
}
