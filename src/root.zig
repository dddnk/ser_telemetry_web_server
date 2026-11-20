//! By convention, root.zig is the root source file when making a package.
const std = @import("std");
const Io = std.Io;
const web = @import("webserver.zig");

/// Ultimate form for speed and correctness, but fixed-size.
/// Listens for data incoming, parses, formats and writes as a webpage.
/// Does not allocate memory at all, making it faster, but has to guess how much memory it will need.
/// This means it can be wrong, and may return WriteFailed if so.
fn listen_serial_webserver(io: std.Io, reader: *std.Io.Reader, line_buffer: []web.PACKET_TYPE, serverctx: *web.WebserverContext) !void {
    std.log.debug("Initial page buffer size: {}", .{serverctx.page_length});
    var counter: u32 = 0;

    while (reader.takeDelimiterExclusive('\n')) |line| {
        reader.toss(1);
        // Skip if in invalid form
        if (web.packet.DataPacket.from_slice_legacy(line)) |pkt| {
            line_buffer[counter % line_buffer.len] = pkt;
            var writer: std.Io.Writer = .fixed(serverctx.webpage_buffer);
            const new_size = try web.format_web_page_writer(&writer, line_buffer);
            std.log.debug("New size: {}", .{new_size});
            serverctx.page_length = new_size;
            counter +%= 1;
        } else |err| {
            std.log.warn("Skipping packet \"{s}\" due to {s}.", .{ line, @errorName(err) });
        }
        try std.Io.sleep(io, serverctx.poll_interval, .real);
    } else |err| {
        if (err != error.EndOfStream) {
            return err;
        }
    }
}
/// Reads the given data, and uses the writing page formatter to write to a given file.
/// Good for debugging, or for sidestepping the need for an http server in memory constrained scenarios.
/// Assumes that it will recieve data piece by piece, inefficient if all done in one go.
pub fn filewriter_server(io: std.Io, gpa: std.mem.Allocator, reader: *std.Io.Reader, out_path: []const u8) !void {
    // Holds incoming packets.
    var line_buffer: std.ArrayList(web.PACKET_TYPE) = try .initCapacity(gpa, 100);
    defer line_buffer.deinit(gpa);

    var page_buffer: std.ArrayList(u8) = try .initCapacity(gpa, web.template.len + 100);
    defer page_buffer.deinit(gpa);
    {
        var buf: [256]u8 = undefined;

        while (reader.takeDelimiterExclusive('\n')) |line| {
            reader.toss(1);
            // Skip if in invalid form
            if (web.packet.DataPacket.from_slice_legacy(line)) |pkt| {
                try line_buffer.append(gpa, pkt);

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
/// Allocates resources ONCE, and shares data across separate threads.
pub fn server_start(io: std.Io, gpa: std.mem.Allocator, reader: *std.Io.Reader, port: u16, page_bufsize: usize, line_cap: usize) !void {
    // Holds incoming packets.
    const line_buffer = try gpa.alloc(web.PACKET_TYPE, line_cap);
    defer gpa.free(line_buffer);
    // For our generated page.
    const page_buffer = try gpa.alloc(u8, page_bufsize);
    defer gpa.free(page_buffer);

    // prerender webpage so there is not an empty page.
    var writer: std.Io.Writer = .fixed(page_buffer);
    const initial_page_size = try web.format_web_page_writer(&writer, line_buffer);
    var wsc: web.WebserverContext = .{ .webpage_buffer = page_buffer, .page_length = initial_page_size, .counter = 0, .poll_interval = .zero };

    var ser_pro: std.Thread = try .spawn(.{}, listen_serial_webserver, .{ io, reader, line_buffer, &wsc });
    defer ser_pro.join();

    try web.start(io, gpa, port, &wsc);
}
// Test stuff
test {
    _ = @import("webserver.zig");
    _ = @import("data_packet.zig");
}
