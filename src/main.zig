const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;

const ser_broadcast = @import("ser_broadcast");
const clap = @import("clap");
const tools = @import("cli_tool.zig");

const DEFAULT_PORT: u16 = 4382;

/// Does zig serial support this operating system?
const zig_serial_supported: bool = std.mem.findScalar(std.Target.Os.Tag, &[_]std.Target.Os.Tag{ .linux, .windows, .macos }, builtin.os.tag) != null;

pub fn main(init: std.process.Init) !void {
    const default_allocator: std.mem.Allocator = init.gpa;
    var iter = try init.minimal.args.iterateAllocator(default_allocator);
    defer iter.deinit();

    _ = iter.next();

    const SubCommands = enum { list, listen, server };
    const main_parsers = .{
        .command = clap.parsers.enumeration(SubCommands),
    };

    // The parameters for `main`. Parameters for the subcommands are specified further down.
    const main_params = comptime clap.parseParamsComptime(
        \\-h, --help  Display this help and exit.
        \\<command>   Run (list (devices) , debug, server)
        \\
    );
    var diag = clap.Diagnostic{};
    var res = clap.parseEx(clap.Help, &main_params, main_parsers, &iter, .{
        .diagnostic = &diag,
        .allocator = default_allocator,
        .terminating_positional = 0,
    }) catch |err| {
        try diag.reportToFile(init.io, .stderr(), err);
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0 or res.positionals[0] == null) return clap.helpToFile(init.io, .stderr(), clap.Help, &main_params, .{});

    const command = res.positionals[0] orelse unreachable;
    switch (command) {
        .list => try tools.list_devices(init.io),
        .listen => try debug_listen(init.io, default_allocator, &iter),
        .server => try server_entry(init.io, default_allocator, &iter),
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
    const server_subcommands = enum { ttyusb, file, stdin };
    const server_parsers = .{
        .method = clap.parsers.enumeration(server_subcommands),
        .u32 = clap.parsers.int(u32, 10),
        .u16 = clap.parsers.int(u16, 10),
        .target_path = clap.parsers.string,
    };
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-b, --baudrate <u32>   The baudrate to listen at. Defaults to 9600.
        \\-p, --port <u16>       The port to start the webserver on. Defaults to 4382.
        \\<method>               What to read the data from available method: (ttyusb, file)
        \\<target_path>          Filename, Device path to connect to.
        \\
    );

    // Here we pass the partially parsed argument iterator.
    var diag = clap.Diagnostic{};
    var results = try clap.parseEx(clap.Help, &params, server_parsers, iter, .{
        .diagnostic = &diag,
        .allocator = gpa,
    });
    defer results.deinit();

    if (results.args.help != 0 or results.positionals[0] == null) return clap.helpToFile(io, .stderr(), clap.Help, &params, .{});
    var read_buffer: [128]u8 = undefined;
    // The port set by arguments, or the default one.
    const decided_port = results.args.port orelse DEFAULT_PORT;

    const source_command = results.positionals[0] orelse unreachable;
    switch (source_command) {
        .ttyusb => {
            // Only works on OS supported by zig-serial.
            if (zig_serial_supported) {
                const source_path = results.positionals[1] orelse return error.MissingPath;
                var serial = try tools.setup_serial(io, source_path, results.args.baudrate);
                defer serial.close(io);

                var reader = serial.reader(io, &read_buffer);

                try ser_broadcast.server_start(io, gpa, &reader.interface, decided_port);
            } else {
                std.log.warn(std.fmt.comptimePrint("TTYUSB source not available on {s}.\n", .{@tagName(builtin.os.tag)}), .{});
            }
        },
        .file => {
            const source_path = results.positionals[1] orelse return error.MissingPath;
            var handle = try std.Io.Dir.cwd().openFile(io, source_path, .{ .mode = .read_only });
            defer handle.close(io);

            var reader = handle.reader(io, &read_buffer);

            try ser_broadcast.server_start(io, gpa, &reader.interface, decided_port);
        },
        .stdin => {
            var handle = std.Io.File.stdin();
            defer handle.close(io);

            var reader = handle.reader(io, &read_buffer);

            try ser_broadcast.server_start(io, gpa, &reader.interface, decided_port);
        },
    }
}
