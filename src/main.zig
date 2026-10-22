const std = @import("std");
const Io = std.Io;

const ser_broadcast = @import("ser_broadcast");
const clap = @import("clap");
const tools = @import("cli_tool.zig");

const SubCommands = enum { list, listen, server, file };

const main_parsers = .{
    .command = clap.parsers.enumeration(SubCommands),
};

// The parameters for `main`. Parameters for the subcommands are specified further down.
const main_params = clap.parseParamsComptime(
    \\-h, --help  Display this help and exit.
    \\<command>
    \\
);
const MainArgs = clap.ResultEx(clap.Help, &main_params, main_parsers);

pub fn main(init: std.process.Init) !void {
    var iter = try init.minimal.args.iterateAllocator(init.gpa);
    defer iter.deinit();

    _ = iter.next();

    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &main_params, main_parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = init.gpa,
        .terminating_positional = 0,
    }) catch |err| {
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    const command = res.positionals[0] orelse return error.MissingCommand;
    switch (command) {
        .list => try tools.list_devices(init.io),
        .listen => try debug_listen(init.io, init.gpa, &iter),
        .server => try server_entry(init.io, init.gpa, &iter),
        .file => try file_entry(init.io, init.gpa, &iter),
    }
}

pub fn debug_listen(io: std.Io, gpa: std.mem.Allocator, iter: *std.process.Args.Iterator) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-b, --baudrate <u32>   The baudrate to listen at. Defaults to 9600.
        \\<str>...
        \\
    );

    // Here we pass the partially parsed argument iterator.
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(io, .stderr(), err);
        return err; // propagate error
    };
    defer res.deinit();

    var serial = try tools.setup_serial(io, res.positionals[0][0], res.args.baudrate);
    defer serial.close(io);

    try tools.debug_listen_serial(io, serial);
}

/// Creates a server to listen from.
pub fn server_entry(io: std.Io, gpa: std.mem.Allocator, iter: *std.process.Args.Iterator) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-b, --baudrate <u32>   The baudrate to listen at. Defaults to 9600.
        \\-p, --port <u16>       The port to start the webserver on. Defaults to 4382.
        \\<str>...
        \\
    );

    // Here we pass the partially parsed argument iterator.
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(io, .stderr(), err);
        return err; // propagate error
    };
    defer res.deinit();

    var serial = try tools.setup_serial(io, res.positionals[0][0], res.args.baudrate);
    defer serial.close(io);

    try ser_broadcast.server_start(io, gpa, serial, res.args.port);
}
/// Creates a server to listen from.
pub fn file_entry(io: std.Io, gpa: std.mem.Allocator, iter: *std.process.Args.Iterator) !void {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\<str>...
        \\
    );

    // Here we pass the partially parsed argument iterator.
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &params, clap.parsers.default, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    }) catch |err| {
        try diag.reportToFile(io, .stderr(), err);
        return err; // propagate error
    };
    defer res.deinit();

    var handle = try std.Io.Dir.cwd().openFile(io, res.positionals[0][0], .{ .mode = .read_only });
    defer handle.close(io);

    try ser_broadcast.server_start(io, gpa, handle, 5882);
}
