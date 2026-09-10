const std = @import("std");
const httpz = @import("httpz");
pub const packet = @import("data_packet.zig");

/// Webpage template
pub const template = @embedFile("./basic.html");
pub const replace_token = "[#vals]";
const replace_start = std.mem.find(u8, template, replace_token) orelse @compileError("could not find token.");

const DEFAULT_PORT: u16 = 5882;
const MAX_WORKERS: u16 = 2;

pub const PACKET_TYPE: type = packet.DataPacket;

const State = struct { log_buffer: *std.ArrayList(u8) };

/// Start http web server
pub fn start(io: std.Io, allocator: std.mem.Allocator, port: ?u16, line_buffer: *std.ArrayList(u8)) !void {
    const final_port = port orelse DEFAULT_PORT;

    var app_state = State{ .log_buffer = line_buffer };

    var server = try httpz.Server(*State).init(io, allocator, .{ .address = .all(final_port), .workers = .{ .count = MAX_WORKERS } }, &app_state);
    defer server.deinit();
    defer server.stop();

    var router = try server.router(.{});
    router.get("/", home_page, .{});

    std.debug.print("Homepage at: http://localhost:{d}\n", .{final_port});

    try server.listen();
}

/// HTML Home page return function
fn home_page(app_state: *State, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .HTML;
    res.body = app_state.log_buffer.items;
    res.header("Access-Control-Allow-Origin", "*");
}

///
pub fn format_web_page(allocator: std.mem.Allocator, lines: []const PACKET_TYPE, buffer: *std.ArrayList(u8)) error{OutOfMemory}!void {
    const separator = "<br>";
    // This is used to keep track of length changes when formatting.
    var word_offset: isize = 0;

    // Clear the buffer first.
    buffer.clearRetainingCapacity();
    try buffer.appendSlice(allocator, template);
    // Temperature logs
    {
        const max_lines: usize = @min(lines.len, 19);
        const offset: usize = lines.len - (max_lines);

        var printed_lines: std.ArrayList(u8) = try .initCapacity(allocator, lines.len * 19);
        defer printed_lines.deinit(allocator);

        for (0..max_lines) |line_id| try printed_lines.print(allocator, "{d:7.2} *C{s}", .{ lines[offset + line_id].temperature, if (line_id != max_lines - 1) separator else "" });
        try buffer.replaceRange(allocator, replace_start, replace_token.len, printed_lines.items);
    } // Shift offset.
    word_offset = @as(isize, @intCast(buffer.items.len)) - @as(isize, @intCast(template.len));
    // Graph
    const graph_token = "[#graph]";
    const graph_token_start = comptime std.mem.find(u8, template, graph_token) orelse @compileError("could not find token for graph.");

    const graph_fragment = try format_webgraph(allocator, lines);
    defer allocator.free(graph_fragment);

    try buffer.replaceRange(allocator, @as(usize, @intCast(@as(isize, @intCast(graph_token_start)) + word_offset)), graph_token.len, graph_fragment);
}

/// Specialized version of the Join function from the standard library
fn joinPrefixSuffix(comptime T: type, allocator: std.mem.Allocator, separator: []const T, slices: []const []const T, prefix: []const T, suffix: []const T) std.mem.Allocator.Error![]T {
    // could be done at comptime?
    const true_sep = try allocator.alloc(T, prefix.len + separator.len + suffix.len);
    defer allocator.free(true_sep);

    @memcpy(true_sep[0..suffix.len], suffix);
    @memcpy(true_sep[suffix.len .. suffix.len + separator.len], separator);
    @memcpy(true_sep[suffix.len + separator.len ..], prefix);

    const total_len = blk: {
        var sum: usize = (true_sep.len * (slices.len - 1)) + (prefix.len + suffix.len);
        for (slices) |slice| sum += slice.len;
        break :blk sum;
    };

    const buf = try allocator.alloc(T, total_len);
    errdefer allocator.free(buf);

    @memcpy(buf[0..prefix.len], prefix);
    var buf_index: usize = prefix.len + slices[0].len;
    @memcpy(buf[prefix.len..buf_index], slices[0]);

    for (slices[1..]) |slice| {
        @memcpy(buf[buf_index .. buf_index + true_sep.len], true_sep);
        buf_index += true_sep.len;
        @memcpy(buf[buf_index .. buf_index + slice.len], slice);
        buf_index += slice.len;
    }
    @memcpy(buf[buf_index..], suffix);

    return buf;
}

pub inline fn lerp(comptime T: type, a: T, b: T, d: T) T {
    return ((b - a) * d) + a;
}

pub inline fn alerp(comptime T: type, a: T, b: T, d: T) T {
    return (d - a) / (b - a);
}

pub inline fn remap(comptime T: type, prev_range: [2]T, neo_range: [2]T, value: T) T {
    return ((neo_range[1] - neo_range[0]) * ((value - prev_range[0]) / (prev_range[1] - prev_range[0]))) + neo_range[0];
    // return lerp(T, neo_range[0], neo_range[1], alerp(T, prev_range[0], prev_range[1], value));
}

/// Creates an svg graph from info.
fn format_webgraph(allocator: std.mem.Allocator, lines: []const PACKET_TYPE) ![]u8 {
    const width: u32 = 500;
    const height: u32 = 210;
    const graph_padding: f32 = 7;
    const text_size: f32 = 7;

    // Get minimum and maximum temperature
    var min_temp: f32 = std.math.inf(f32);
    var max_temp: f32 = -std.math.inf(f32);
    for (lines) |packet_line| {
        min_temp = @min(min_temp, packet_line.temperature);
        max_temp = @max(max_temp, packet_line.temperature);
    }

    var temp_lines: std.ArrayList(u8) = try .initCapacity(allocator, 100 + (lines.len * 6));
    defer temp_lines.deinit(allocator);
    try temp_lines.print(allocator, "<svg height=\"{}\" width=\"{}\" viewbox=\"0 0 {} {}\">\n", .{ height, width, width, height });

    {
        try temp_lines.print(allocator, "<polyline points=\"", .{});

        for (lines, 0..) |packet_lines, idx| {
            try temp_lines.print(allocator, " {},{} ", .{ remap(f32, [2]f32{ 0, @floatFromInt(lines.len - 1) }, [2]f32{ 0, @floatFromInt(width) }, @floatFromInt(idx)), remap(f32, .{ min_temp, max_temp }, .{ @as(f32, @floatFromInt(height)) - graph_padding, graph_padding }, packet_lines.temperature) });
        }

        try temp_lines.print(allocator, "\" style=\"fill:none;stroke:var(--foreground-colour);stroke-width:1\" />", .{});
    }
    // Min and max legend
    try temp_lines.print(allocator, "<text x=\"0\" y=\"{}\" fill=\"var(--foreground-colour)\" font-size=\"{}\" \">{} *C</text>", .{ text_size, text_size, max_temp });
    try temp_lines.print(allocator, "<text x=\"0\" y=\"{}\" fill=\"var(--foreground-colour)\" font-size=\"{}\" \">{} *C</text>", .{ height, text_size, min_temp });

    try temp_lines.print(allocator, "</svg>", .{});
    return temp_lines.toOwnedSlice(allocator);
}

test "joinPrefixSuffix" {
    const testing = std.testing;
    const words = .{ "foo", "bar" };

    const total = try joinPrefixSuffix(u8, testing.allocator, ",", &words, "[", "]");
    defer testing.allocator.free(total);

    try testing.expectEqualStrings("[foo],[bar]", total);
}

test "remap_function" {
    // Iterate through all float types
    inline for ([_]type{ f16, f32, f64, f128 }) |float| {
        const old_ranges = [_][2]float{ .{ -2, 2 }, .{ 0, -1 } };
        const new_ranges = [_][2]float{ .{ -1, 1 }, .{ -1, 0 } };
        const initial_values = [_]float{ 0, -0.2 };
        const expected_values = [_]float{ 0, -0.8 };

        const iter_len: usize = @max(@max(old_ranges.len, new_ranges.len), @max(initial_values.len, expected_values.len));

        for (0..iter_len) |idx| {
            const ground_res = (lerp(float, new_ranges[idx][0], new_ranges[idx][1], alerp(float, old_ranges[idx][0], old_ranges[idx][1], initial_values[idx])));
            const remap_res = remap(float, old_ranges[idx], new_ranges[idx], initial_values[idx]);
            try std.testing.expect(ground_res == expected_values[idx]);
            try std.testing.expect(remap_res == expected_values[idx]);
        }
    }
}
