//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;
const web = @import("webserver.zig");

/// Listens for data incoming, parses, formats and writes as a webpage.
/// When it creates the memory, it allocates as it writes, making it reliable, but slightly slower.
/// Older version.
fn listen_serial_webserver(alloc: std.mem.Allocator, reader: *std.Io.Reader, line_buffer: *std.ArrayList(web.PACKET_TYPE), serverctx: *web.WebserverContext) !void {
    while (reader.takeDelimiterExclusive('\n')) |line| {
        reader.toss(1);
        // Skip if in invalid form
        if (web.packet.DataPacket.from_slice_legacy(line)) |pkt| {
            try line_buffer.append(alloc, pkt);
            try web.format_web_page(alloc, line_buffer.items, serverctx.webpage_buffer);
        } else |err| {
            std.log.warn("Skipping packet \"{s}\" due to {s}.", .{ line, @errorName(err) });
        }
    } else |err| {
        if (err != error.EndOfStream) {
            return err;
        }
    }
}
/// Listens for data incoming, parses, formats and writes as a webpage.
/// Allocates memory once per read cycle, making it faster, but has to guess how much memory it will need.
/// This means it can be wrong, and may return WriteFailed if so.
fn listen_serial_webserver_writer(alloc: std.mem.Allocator, reader: *std.Io.Reader, line_buffer: *std.ArrayList(web.PACKET_TYPE), serverctx: *web.WebserverContext) !void {
    std.log.debug("Initial page buffer size: {}", .{serverctx.page_length});

    while (reader.takeDelimiterExclusive('\n')) |line| {
        reader.toss(1);
        // Skip if in invalid form
        if (web.packet.DataPacket.from_slice_legacy(line)) |pkt| {
            try line_buffer.append(alloc, pkt);
            // try serverctx.webpage_buffer.resize(alloc, serverctx.page_length + (line.len * 2));
            var writer: std.Io.Writer = .fromArrayList(serverctx.webpage_buffer);
            const new_size = try web.format_web_page_writer(&writer, line_buffer.items);
            std.log.debug("New size: {}", .{new_size});
            serverctx.page_length = new_size;
        } else |err| {
            std.log.warn("Skipping packet \"{s}\" due to {s}.", .{ line, @errorName(err) });
        }
    } else |err| {
        if (err != error.EndOfStream) {
            return err;
        }
    }
}

/// Reads the given data, and uses the writing page formatter to write to a given file.
/// Good for debugging, or for sidestepping the need for an http server in memory constrained scenarios.
/// Assumes that it will recieve data piece by piece, inefficient if all done in one go.
pub fn filewriter_server(io: std.Io, allocator: std.mem.Allocator, reader: *std.Io.Reader, out_path: []const u8) !void {
    // Holds incoming packets.
    var line_buffer: std.ArrayList(web.PACKET_TYPE) = try .initCapacity(allocator, 100);
    defer line_buffer.deinit(allocator);

    var page_buffer: std.ArrayList(u8) = try .initCapacity(allocator, web.template.len + 100);
    defer page_buffer.deinit(allocator);
    {
        var buf: [256]u8 = undefined;

        while (reader.takeDelimiterExclusive('\n')) |line| {
            reader.toss(1);
            // Skip if in invalid form
            if (web.packet.DataPacket.from_slice_legacy(line)) |pkt| {
                try line_buffer.append(allocator, pkt);

                var file_handle = try std.Io.Dir.cwd().openFile(io, out_path, .{ .mode = .write_only });
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
}

/// Initializes and runs the web server and serial reader & formatter.
/// Allocates resources, and shares data across separate threads.
pub fn server_start(io: std.Io, allocator: std.mem.Allocator, reader: *std.Io.Reader, port: u16) !void {
    const initial_page_size: usize = web.template.len + 100;
    // Holds incoming packets.
    var line_buffer: std.ArrayList(web.PACKET_TYPE) = try .initCapacity(allocator, 100);
    defer line_buffer.deinit(allocator);
    // For our generated page.
    var page_buffer: std.ArrayList(u8) = try .initCapacity(allocator, initial_page_size);
    defer page_buffer.deinit(allocator);

    // prerender webpage so there is not an empty page.
    try web.format_web_page(allocator, line_buffer.items, &page_buffer);
    var wsc: web.WebserverContext = .{ .webpage_buffer = &page_buffer, .page_length = initial_page_size };

    var ser_pro: std.Thread = try .spawn(.{}, listen_serial_webserver, .{ allocator, reader, &line_buffer, &wsc });
    // var ser_pro: std.Thread = try .spawn(.{}, listen_serial_webserver_writer, .{ allocator, reader, &line_buffer, &wsc });
    defer ser_pro.join();

    try web.start(io, allocator, port, &wsc);
}

// Test stuff
test {
    _ = @import("webserver.zig");
    _ = @import("data_packet.zig");
}
