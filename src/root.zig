//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;
const web = @import("webserver.zig");

/// Listens to a stream of data. For webserver.
fn listen_serial(alloc: std.mem.Allocator, reader: *std.Io.Reader, line_buffer: *std.ArrayList(web.PACKET_TYPE), page_buffer: *std.ArrayList(u8)) !void {
    while (reader.takeDelimiterExclusive('\n')) |line| {
        reader.toss(1);
        // Skip if in invalid form
        if (web.packet.DataPacket.from_slice_legacy(line)) |pkt| {
            try line_buffer.append(alloc, pkt);
            try web.format_web_page(alloc, line_buffer.items, page_buffer);
        } else |err| {
            std.log.warn("Skipping packet \"{s}\" due to {s}.", .{ line, @errorName(err) });
        }
    } else |err| {
        if (err != error.EndOfStream) {
            return err;
        }
    }
}

fn listen_serial_file(io: std.Io, alloc: std.mem.Allocator, reader: *std.Io.Reader, line_buffer: *std.ArrayList(web.PACKET_TYPE), path: []const u8) !void {
    var buf: [256]u8 = undefined;

    while (reader.takeDelimiterExclusive('\n')) |line| {
        reader.toss(1);
        // Skip if in invalid form
        if (web.packet.DataPacket.from_slice_legacy(line)) |pkt| {
            try line_buffer.append(alloc, pkt);

            var file_handle = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .write_only });
            defer file_handle.close(io);

            var writer_wrapper = file_handle.writer(io, &buf);

            _ = try web.format_web_page_writer(&writer_wrapper.interface, line_buffer.items);
        } else |err| {
            std.log.warn("Skipping packet \"{s}\" due to {s}.", .{ line, @errorName(err) });
        }
    } else |err| {
        if (err != error.EndOfStream) {
            return err;
        }
    }
}

pub fn filewriter_server(io: std.Io, allocator: std.mem.Allocator, reader: *std.Io.Reader, out_path: []const u8) !void {
    // Holds incoming packets.
    var line_buffer: std.ArrayList(web.PACKET_TYPE) = try .initCapacity(allocator, 100);
    defer line_buffer.deinit(allocator);
    var page_buffer: std.ArrayList(u8) = try .initCapacity(allocator, web.template.len + 100);
    defer page_buffer.deinit(allocator);

    try listen_serial_file(io, allocator, reader, &line_buffer, out_path);
}

/// Start web server, listening to serial.
pub fn server_start(io: std.Io, allocator: std.mem.Allocator, reader: *std.Io.Reader, port: u16) !void {
    // Holds incoming packets.
    var line_buffer: std.ArrayList(web.PACKET_TYPE) = try .initCapacity(allocator, 100);
    defer line_buffer.deinit(allocator);
    // For our generated page.
    var page_buffer: std.ArrayList(u8) = try .initCapacity(allocator, web.template.len + 100);
    defer page_buffer.deinit(allocator);

    // prerender webpage so there is not an empty page.
    try web.format_web_page(allocator, line_buffer.items, &page_buffer);

    var ser_pro: std.Thread = try .spawn(.{}, listen_serial, .{ allocator, reader, &line_buffer, &page_buffer });
    defer ser_pro.join();

    var wsc: web.WebserverContext = .{ .log_buffer = &page_buffer, .page_length = 0 };
    try web.start(io, allocator, port, &wsc);
}

// Test stuff
test {
    _ = @import("webserver.zig");
    _ = @import("data_packet.zig");
}
