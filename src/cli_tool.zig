const std = @import("std");
const builtin = @import("builtin");
const Io = std.Io;
const zig_serial = @import("serial");

const READ_BUFFER_SIZE: usize = 128;

/// Listens to the serial stream line-by line for debug purposes.
pub fn debug_listen_serial(io: std.Io, serial: std.Io.File) !void {
    var r_buf: [READ_BUFFER_SIZE]u8 = undefined;
    var reader = serial.reader(io, &r_buf);

    // Read through the input stream
    while (reader.interface.takeDelimiterExclusive('\n')) |line| {
        reader.interface.toss(1);
        std.debug.print("\u{001b}[33m[{d}] >> \u{001b}[0m{s}\n", .{ std.Io.Timestamp.now(io, .boot).toSeconds(), line });
    } else |err| {
        if (err != error.EndOfStream) {
            return err;
        }
    }
}
/// Returns a list of available devices
pub fn list_devices(io: std.Io) !void {
    // MacOS does not support this.
    if (builtin.os.tag == .linux or builtin.os.tag == .windows) {
        var iterator = try zig_serial.list(io);
        defer iterator.deinit();

        while (try iterator.next()) |port| {
            std.debug.print("path={s},\tname={s},\tdriver={s}\n", .{ port.file_name, port.display_name, port.driver orelse "<no driver recognized>" });
        }
    } else {
        std.debug.print(std.fmt.comptimePrint("List feature not available on {s}.\n", .{@tagName(builtin.os.tag)}), .{});
    }
}
/// Opens device and configure it as a serial port.
pub fn setup_serial(io: std.Io, device: []const u8, baudrate: ?u32) !std.Io.File {
    const serial = std.Io.Dir.cwd().openFile(io, device, .{ .mode = .read_write }) catch |err| {
        if (err == error.FileNotFound) {
            std.debug.print("\u{001b}[31mError: The Device [{s}] was not found.\u{001b}[0m\n", .{device});
        }
        return err;
    };

    try zig_serial.configureSerialPort(serial, zig_serial.SerialConfig{
        .baud_rate = baudrate orelse 9600,
        .word_size = .eight,
        .parity = .none,
        .stop_bits = .one,
        .handshake = .none,
    });
    errdefer serial.close(io);
    std.debug.print("Listening at [\u{001b}[33m{s}\u{001b}[0m], baudrate \u{001b}[32m{}\u{001b}[0m\n", .{ device, baudrate orelse 9600 });
    return serial;
}
