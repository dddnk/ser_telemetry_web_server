//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;
const zig_serial = @import("serial");
const web = @import("webserver.zig");

fn listen_serial(io: std.Io, alloc: std.mem.Allocator, device: std.Io.File, line_buffer: *std.ArrayList(web.PACKET_TYPE), page_buffer: *std.ArrayList(u8)) !void {
    var r_buf: [64]u8 = undefined;
    var reader = device.reader(io, &r_buf);

    while (reader.interface.takeDelimiterExclusive('\n')) |line| {
        reader.interface.toss(1);
        // Skip if in invalid form
        if (web.packet.DataPacket.from_slice(line)) |pkt| {
            try line_buffer.append(alloc, pkt);
        } else |_| {
            std.debug.print("Skipping packet... [{s}] is malformed or unreadable.", .{line});
        }
        try web.format_web_page(alloc, line_buffer.items, page_buffer);
    } else |err| {
        if (err != error.EndOfStream) {
            return err;
        }
    }
}

/// Start web server
pub fn server_start(io: std.Io, allocator: std.mem.Allocator, device: std.Io.File, port: ?u16) !void {
    var line_buffer: std.ArrayList(web.PACKET_TYPE) = try .initCapacity(allocator, 100);
    defer line_buffer.deinit(allocator);
    var page_buffer: std.ArrayList(u8) = try .initCapacity(allocator, 100);
    defer page_buffer.deinit(allocator);

    // prerender webpage so there is not an empty page.
    try web.format_web_page(allocator, line_buffer.items, &page_buffer);

    var ser_pro: std.Thread = try .spawn(.{}, listen_serial, .{ io, allocator, device, &line_buffer, &page_buffer });
    defer ser_pro.join();

    try web.start(io, allocator, port, &page_buffer);
}

// Test stuff
test {
    _ = @import("webserver.zig");
    _ = @import("data_packet.zig");
}
