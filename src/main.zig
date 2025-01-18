const std = @import("std");
const cl = @import("cl");

pub const Say = struct {
    pub const name = "say";
    pub const desc = "Write message the to console. Writes 'Hello, World!' if there is no message specified";

    pub const args = &.{"msg"};
    pub fn run(message: ?[]const u8) void {
        if (message) |msg| {
            std.debug.print("{s}\n", .{msg});
        } else {
            std.debug.print("Hello, World!\n", .{});
        }
    }
};

pub const Throw = struct {
    pub const name = "throw";
    pub const desc = "Exit with an error";

    pub const args = &.{"c"};
    pub fn run(code: ?u8) void {
        const c = code orelse 255;
        std.process.exit(c);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();

    var args = std.ArrayList([]const u8).init(allocator);
    defer args.deinit();

    while (args_iter.next()) |arg| {
        try args.append(arg);
    }

    const res = cl.parse(@This(), args.items);

    res.run();
}
