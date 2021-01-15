# zig-csv ![CI](https://github.com/beho/zig-csv/workflows/CI/badge.svg)

Low-level CSV parser library for [Zig language](https://github.com/ziglang/zig). Each non-empty line in input is parsed as one or more tokens of type `field`, followed by `row_end`.

## Features

- Reads UTF-8 files.
- Provides iterator interface to stream of tokens. 
- Handles quoted fields in which column/row separator can be used. Quote itself can be used in field by doubling it (e.g. `"This is quote: ""."`)
- Configurable column separator(default `,`), row separator (`\n`) and quote (`"`). 
    - **Currently only single byte characters.**
- Parser does not allocate – caller provides a buffer that parser operates in. **Buffer must be longer than a longest field in input.**

## Example

Following code reads CSV tokens from a file while very naively printing them as table to standard output. 

```zig
const std = @import("std");
const csv = @import("csv");

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = &arena.allocator;
    var buffer = try allocator.alloc(u8, 4096);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.log.warn("Single arg is expected", .{});
        std.process.exit(1);
    }

    const file = try std.fs.cwd().openFile(args[1], .{});
    defer file.close();

    const csv_tokenizer = &try csv.CsvTokenizer(std.fs.File.Reader).init(file.reader(), buffer, .{});
    const stdout = std.io.getStdOut().writer();

    while (try csv_tokenizer.next()) |token| {
        switch (token) {
            .field => |val| {
                try stdout.writeAll(val);
                try stdout.writeAll("\t");
            },
            .row_end => {
                try stdout.writeAll("\n");
            },
        }
    }
}
```
