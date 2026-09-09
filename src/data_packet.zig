const std = @import("std");

/// Datapacket type. Lines are read and parsed into this datatype.
pub const DataPacket = struct {
    temperature: f32,

    const Self = @This();

    // Constructor.
    pub fn from_slice(input_slice: []const u8) std.fmt.ParseFloatError!Self {
        // Looks like this: [TEMP=017.57 C]
        const temp = try std.fmt.parseFloat(@FieldType(Self, "temperature"), input_slice[6..12]);
        return Self{ .temperature = temp };
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
