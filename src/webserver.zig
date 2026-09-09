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

    // prerender webpage so there is not an empty page.

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

    const max_lines: usize = @min(lines.len, 19);
    const offset: usize = lines.len - (max_lines);

    var printed_lines: std.ArrayList(u8) = try .initCapacity(allocator, lines.len * 19);
    defer printed_lines.deinit(allocator);

    for (0..max_lines) |line_id| {
        try printed_lines.print(allocator, "{d:7.2} *C{s}", .{ lines[offset + line_id].temperature, if (line_id != max_lines - 1) separator else "" });
    }

    buffer.clearRetainingCapacity();
    try buffer.appendSlice(allocator, template);
    try buffer.replaceRange(allocator, replace_start, replace_token.len, printed_lines.items);
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

test "joinPrefixSuffix" {
    const testing = std.testing;
    const words = .{ "foo", "bar" };

    const total = try joinPrefixSuffix(u8, testing.allocator, ",", &words, "[", "]");
    defer testing.allocator.free(total);

    try testing.expectEqualStrings("[foo],[bar]", total);
}
