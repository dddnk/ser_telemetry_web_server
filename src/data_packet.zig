const std = @import("std");

const example_schema = "[TEMP=000.00 C]";

const field_1 = range_finder(u8, example_schema, .{ '0', ' ' }, 0) orelse @compileError("Could not find indexes for field 1");

///Used for finding indexes of fields at compile time.
fn range_finder(comptime T: type, slice: []const T, tokens: [2]T, offset: usize) ?[2]usize {
    const first = std.mem.findScalarPos(T, slice, offset, tokens[0]) orelse return null;
    const last = std.mem.findScalarPos(T, slice, first, tokens[1]) orelse return null;
    return [2]usize{ first, last };
}

/// Datapacket type. Lines are read and parsed into this datatype.
pub const DataPacket = struct {
    temperature: f32,
    seconds: ?f32,

    const Self = @This();

    // Constructor.
    pub fn from_slice(input_slice: []const u8) std.fmt.ParseFloatError!Self {
        const temp = try std.fmt.parseFloat(@FieldType(Self, "temperature"), input_slice[field_1[0]..field_1[1]]);
        return Self{ .temperature = temp, .seconds = null };
    }
};

test "DataPacket Construct" {
    const input_slices = [_]*const [15:0]u8{ "[TEMP=017.17 C]", "[TEMP=167.00 C]", "[TEMP=018.12 C]", "[TEMP=-01.00 C]" };
    const matching = [_]f32{ 17.17, 167.0, 18.12, -1.0 };

    for (input_slices, 0..) |slice, idx| {
        const packet: DataPacket = try .from_slice(slice);
        try std.testing.expectApproxEqAbs(packet.temperature, matching[idx], 0.11);
    }
}
