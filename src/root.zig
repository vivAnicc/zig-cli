const std = @import("std");
pub const commands = @import("commands.zig");
const parse_args = @import("args.zig").parse_args;

pub fn parse(namespace: type, args: []const []const u8) commands.ParseResult(namespace) {
    const ReturnType = commands.ParseResult(namespace);

    const Res = struct {
        fn err(a: []const []const u8, e: commands.CommandErrorUnion(namespace)) ReturnType {
            return .{ .Error = .{ .exe = a[0], .err = e } };
        }

        fn help(h: commands.HelpCommand(namespace)) ReturnType {
            return .{ .Help = h };
        }
    };

    const Commands = commands.Commands(namespace);

    std.debug.assert(args.len > 0);

    if (args.len == 1) {
        return Res.err(args, .MissingCommand);
    }

    const command_name = args[1];

    if (std.mem.eql(u8, command_name, "help")) {
        return Res.help(.{ .args = args, .command = null });
    }

    inline for (@typeInfo(Commands).Union.fields) |field| {
        if (std.mem.eql(u8, command_name, field.name)) {
            const args_type = @typeInfo(field.type).Struct.fields[0].type;
            const PayloadType = std.meta.TagPayloadByName(Commands, field.name);

            var command = @unionInit(Commands, field.name, .{
                .args = undefined,
            });

            const command_args = switch (parse_args(args[2..], PayloadType.params, args_type)) {
                .Ok => |ok| ok,
                .Err => |err| switch (err) {
                    .MissingArgumentValue => |e| return Res.err(args, .{ .InvalidArgumentType = .{ .cmd = command, .arg = e } }),
                    .InvalidArgument => |e| return Res.err(args, .{ .InvalidArgument = .{ .cmd = command, .arg = e } }),
                    .MissingArgument => |e| return Res.err(args, .{ .MissingArgument = .{ .cmd = command, .arg = e } }),
                    .TooManyArguments => |e| return Res.err(args, .{ .TooManyArguments = .{ .cmd = command, .args = e } }),
                    .ParseError => |e| return Res.err(args, .{ .InvalidArgumentType = .{ .cmd = command, .arg = e } }),
                }
            };

            command= @unionInit(Commands, field.name, .{
                .args = command_args,
            });

            return .{ .Command = command };
        }
    }

    return Res.err(args, .{ .UnknownCommand = command_name });
}

pub fn run(command: anytype) void {
    const Type = @TypeOf(command);
    if (std.meta.hasFn(Type, "run")) {
        command.run();
        return;
    }

    const active = std.meta.activeTag(command);
    inline for (@typeInfo(Type).Union.fields) |field| {
        if (active == std.meta.stringToEnum(std.meta.Tag(Type), field.name)) {
            run(@field(command, field.name));
            return;
        }
    }

    unreachable;
}
