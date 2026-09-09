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

// test "DataPacket Construct" {

// }
