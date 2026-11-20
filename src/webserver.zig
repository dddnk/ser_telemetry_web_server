const std = @import("std");
const httpz = @import("httpz");
pub const packet = @import("data_packet.zig");

/// Webpage template
pub const template = @embedFile("./basic.html");
pub const replace_token = "[#vals]";
const replace_start = std.mem.find(u8, template, replace_token) orelse @compileError("could not find token.");

const MAX_WORKERS: u16 = 2;

pub const PACKET_TYPE: type = packet.DataPacket;

pub const WebserverContext = struct { webpage_buffer: []u8, page_length: usize, counter: u32, poll_interval: std.Io.Duration };

/// Start http web server
pub fn start(io: std.Io, allocator: std.mem.Allocator, port: u16, app_state: *WebserverContext) !void {
    var server = try httpz.Server(*WebserverContext).init(io, allocator, .{ .address = .all(port), .workers = .{ .count = MAX_WORKERS } }, app_state);
    defer server.deinit();
    defer server.stop();

    var router = try server.router(.{});
    router.get("/", home_page, .{});

    std.debug.print("Homepage at: \u{001b}[34mhttp://localhost:{d}\u{001b}[0m\n", .{port});

    try server.listen();
}

/// HTML Home page return function
fn home_page(app_state: *WebserverContext, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .HTML;
    res.body = app_state.webpage_buffer[0..app_state.page_length];
    res.header("Access-Control-Allow-Origin", "*");
}

const WebgraphConfig = struct {
    width: u32,
    height: u32,
    graph_padding: f32,
    text_size: f32,
};

/// Formats an html webpage from the given packets.
/// Uses a writer given to it, so it uses the memory it is given, and does not allocate.
/// Returns the final size of the webpage.
/// Faster and more versatile, but needs to be given enough memory to work with.
pub fn format_web_page_writer(writer: *std.Io.Writer, lines: []const PACKET_TYPE) !usize {
    const prior_length = writer.end;
    const separator = "<br>";
    // This is used to keep track of length changes when formatting.
    var word_offset: isize = 0;
    _ = try writer.write(template[0..replace_start]);

    // Temperature logs
    for (lines, 0..) |line, line_id| {
        try writer.print("{d:7.2} *C{s}", .{ line.temperature, if (line_id != lines.len - 1) separator else "" });
    }
    // Shift offset.
    word_offset = @as(isize, @intCast(writer.end)) - @as(isize, @intCast(template.len));
    // Graph
    const graph_token = "[#graph]";
    const graph_token_start = comptime std.mem.find(u8, template, graph_token) orelse @compileError("could not find token for graph.");

    // Write upto the graph part
    _ = try writer.write(template[replace_start + replace_token.len .. graph_token_start]);

    // --------------
    // WRITE_WEBGRAPH
    // --------------

    const sizing = WebgraphConfig{
        .width = 500,
        .height = 210,
        .graph_padding = 7,
        .text_size = 7,
    };

    // Get minimum and maximum temperature
    var min_temp: f32 = std.math.inf(f32);
    var max_temp: f32 = -std.math.inf(f32);
    for (lines) |packet_line| {
        min_temp = @min(min_temp, packet_line.temperature);
        max_temp = @max(max_temp, packet_line.temperature);
    }
    try writer.print("<svg viewbox=\"0 0 {} {}\">\n<polyline points=\"", .{ sizing.width, sizing.height });
    for (lines, 0..) |packet_lines, idx| {
        try writer.print(" {d:7.2},{d:7.2} ", .{ remap(f32, [2]f32{ 0, @floatFromInt(lines.len - 1) }, .{ sizing.graph_padding, @as(f32, @floatFromInt(sizing.width)) - sizing.graph_padding }, @floatFromInt(idx)), remap(f32, .{ min_temp, max_temp }, .{ @as(f32, @floatFromInt(sizing.height)) - sizing.text_size, sizing.text_size }, packet_lines.temperature) });
    }
    try writer.print("\" style=\"fill:none;stroke:var(--foreground-colour);vector-effect: non-scaling-stroke;stroke-width:1px\" />", .{});
    // Min and max legend
    try writer.print("<text x=\"0\" y=\"{}\" fill=\"var(--foreground-colour)\" font-size=\"{}\" \">{d:7.2} *C</text>", .{ sizing.text_size, sizing.text_size, max_temp });
    try writer.print("<text x=\"0\" y=\"{}\" fill=\"var(--foreground-colour)\" font-size=\"{}\" \">{d:7.2} *C</text>", .{ sizing.height, sizing.text_size, min_temp });

    try writer.print("</svg>", .{});
    // -----------------
    // WRITE_WEBGRAPH_END
    // -----------------

    _ = try writer.write(template[graph_token_start + graph_token.len ..]);
    try writer.flush();

    return writer.end - prior_length;
}

pub inline fn remap(comptime T: type, prev_range: [2]T, neo_range: [2]T, value: T) T {
    return ((neo_range[1] - neo_range[0]) * ((value - prev_range[0]) / (prev_range[1] - prev_range[0]))) + neo_range[0];
}

test "webgraph procedure && dummy write" {
    const alloc = std.testing.allocator;
    const dummy_buffer_size: usize = 64;

    var points: std.ArrayList(u8) = try .initCapacity(alloc, template.len);
    defer points.deinit(alloc);
    try points.resize(alloc, dummy_buffer_size);

    const count: usize = 100_000;
    var pkt_list: [count]PACKET_TYPE = undefined;
    for (0..count) |idx| {
        pkt_list[idx] = PACKET_TYPE{ .seconds = null, .temperature = remap(f32, .{ 0, @floatFromInt(count) }, .{ -15.0, 100.0 }, @floatFromInt(idx)) };
    }

    var dummywriter: std.Io.Writer.Discarding = .init(points.items[0..dummy_buffer_size]);
    _ = try format_web_page_writer(&dummywriter.writer, &pkt_list);
    const dummy_out = dummywriter.count;

    try points.resize(alloc, dummy_out + 16);
    var writer: std.Io.Writer = .fixed(points.items);
    const writer_out = try format_web_page_writer(&writer, &pkt_list);

    try std.testing.expectEqual(writer_out, dummy_out);
}

test "remap_function" {
    // Iterate through all float types
    inline for ([_]type{ f16, f32, f64, f80, f128 }) |float| {
        const old_ranges = [_][2]float{ .{ -2, 2 }, .{ 0, -1 } };
        const new_ranges = [_][2]float{ .{ -1, 1 }, .{ -1, 0 } };
        const initial_values = [_]float{ 0, -0.2 };
        const expected_values = [_]float{ 0, -0.8 };

        for (0..old_ranges.len) |idx| {
            const remap_res = remap(float, old_ranges[idx], new_ranges[idx], initial_values[idx]);
            try std.testing.expect(remap_res == expected_values[idx]);
        }
    }
}
