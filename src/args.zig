const std = @import("std");

pub const ParsingError = union(enum) {
    MissingArgumentValue: []const u8,
    InvalidArgument: []const u8,
    MissingArgument: []const u8,
    TooManyArguments: []const []const u8,
    ParseError: []const u8,
};

fn ReturnType(comptime t: type) type {
    return union(enum) {
        Err: ParsingError,
        Ok: t,

        pub fn cast_tuple(self: @This(), ret: type) ReturnType(std.meta.Tuple(&.{ret, usize})) {
            switch (self) {
                .Err => |err| return .{ .Err = err },
                .Ok => |o| return .{ .Ok = @as(std.meta.Tuple(&.{ret, usize}), o) },
            }
        }
    };
}

pub fn parse_args(args: []const []const u8, comptime arg_names: []const []const u8, comptime args_tuple_type: type)
    ReturnType(args_tuple_type) {

    const args_info = @typeInfo(args_tuple_type).Struct;
    std.debug.assert(args_info.is_tuple);
    std.debug.assert(args_info.fields.len == arg_names.len);

    const args_fields = args_info.fields;
    comptime var args_types: [args_fields.len]type = undefined;
    inline for (args_fields, 0..) |field, idx| {
        args_types[idx] = field.type;
    }

    var tuple: args_tuple_type = undefined;
    var visited = [_]bool{false} ** args_types.len;
    var args_idx: usize = 0;
    outer: while (args_idx < args.len) {
        inline for (args_types, 0..) |arg_type, tuple_idx| {
            var ok = true;

            if (visited[tuple_idx]) {
                ok = false;
            }

            const arg_value_maybe = if (ok)
                parse_arg(args[args_idx..], 0, arg_names[tuple_idx], null, arg_type)
                catch Catch: {
                    ok = false;
                    break :Catch undefined;
                } else undefined;

            if (ok) {
                switch (arg_value_maybe) {
                    .Ok => |arg_value| {
                        tuple[tuple_idx] = arg_value[0];
                        visited[tuple_idx] = true;
                        args_idx += arg_value[1];
                        continue :outer;
                    },
                    .Err => |err| return .{ .Err = err },
                }
            }
        }

        return .{ .Err = .{ .InvalidArgument = args[args_idx] } };
    }

    inline for (visited, 0..) |v, idx| {
        if (!v) {
            if (is_required(arg_names[idx], args_types[idx])) {
                return .{ .Err = .{ .MissingArgument = arg_names[idx] } };
            } else {
                tuple[idx] = get_default(args_types[idx]) catch unreachable;
            }
        }
    }

    return .{ .Ok = tuple };
}

fn is_required(name: []const u8, arg_type: type) bool {
    _ = name;
    if (@typeInfo(arg_type) == .Optional) {
        return false;
    }

    return true;
}

fn get_default(arg_type: type) !arg_type {
    if (@typeInfo(arg_type) == .Optional) {
        return null;
    }

    return error.NoDefault;
}

// pos_idx is the amount of positional arguments that were parsed before this one
// arg_idx is the idx of the positional argument and it is null if the argument isn't positional
fn parse_arg(args: []const []const u8, pos_idx: usize, comptime name: []const u8,
    arg_idx: ?usize, comptime arg_type: type) !ReturnType(std.meta.Tuple(&.{arg_type, usize})) {

    std.debug.assert(args.len > 0);

    if (arg_idx) |idx| {
        _ = idx;
        _ = pos_idx;
        @panic("Not implemented");
    }

    const first = args[0];

    if (!std.mem.startsWith(u8, first, "-")) {
        return error.NotFound;
    }

    if (!std.mem.eql(u8, name, first[1..])) {
        return error.NotFound;
    }

    if (arg_type == ?void) {
        return .{ .Ok = .{void{}, 1} };
    }

    const res = switch (parse_type(args[1..], arg_type)) {
        .Ok => |ok| ok,
        .Err => |err| switch (err) {
            .MissingArgumentValue => return .{ .Err = .{ .MissingArgumentValue = name } },
            .ParseError => return .{ .Err = .{ .ParseError = name } },
            else => |e| return .{ .Err = e },
        },
    };
    return .{ .Ok = .{res[0], 1 + res[1]} };
}

fn parse_type(args: []const []const u8, comptime arg_type: type) ReturnType(std.meta.Tuple(&.{arg_type, usize})) {
    if (arg_type == []const u8) {
        const val = if (args.len != 0) args[0] else return .{ .Err = .{ .MissingArgumentValue = "!" } };
        return .{ .Ok = .{val, 1} };
    }

    const info = @typeInfo(arg_type);

    switch (info) {
        .Optional => |opt| {
            if (args.len > 0 and std.mem.eql(u8, args[0], "null")) {
                return .{ .Ok = .{null, 1} };
            }
            return parse_type(args, opt.child).cast_tuple(arg_type);
        },
        .Int => {
            const val = if (args.len != 0) args[0] else return .{ .Err = .{ .MissingArgumentValue = "!" } };
            return .{ .Ok = .{std.fmt.parseInt(arg_type, val, 10) catch return .{ .Err = .{ .ParseError = "!" } }, 1} };
        },
        .Void => return .{ .Ok = .{ void{}, 0 } },
        .Bool => {
            const val = if (args.len != 0) args[0] else return error.MissingArgumentValue;
            if (std.mem.eql(u8, val, "true")) {
                return .{true, 1};
            } else if (std.mem.eql(u8, val, "false")) {
                return .{false, 1};
            } else {
                return error.ParseError;
            }
        },
        .Null => unreachable,
        .Enum => |e| {
            const first = if (args.len != 0) args[0] else return error.MissingArgumentValue;
            const val = if (std.mem.startsWith(u8, first, ".")) first[1..] else first;

            inline for (e.fields) |field| {
                if (std.mem.eql(u8, val, field.name)) {
                    return .{@enumFromInt(field.value), 1};
                }
            }

            return error.ParseError;
        },
        .Float => {
            const val = if (args.len != 0) args[0] else return error.MissingArgumentValue;
            return .{std.fmt.parseFloat(arg_type, val) catch return error.ParseError, 1};
        },
        .Array => |array| {
            const open = if (args.len != 0) args[0] else return error.MissingArgumentValue;
            if (!std.mem.eql(u8, open, "[")) {
                return ParsingError;
            }
            if (args.len < 2) {
                return ParsingError;
            }

            var arg_idx: usize = 1;
            const res: arg_type = undefined;
            var res_idx: usize = 0;
            while (arg_idx < args.len) {
                const elem = try parse_type(args[arg_idx..], array.child);
                res[res_idx] = elem[0];
                res_idx += 1;
                arg_idx += elem[1];

                // Optionals arguments can be skipped to signify null, in that case advance manually
                if (@typeInfo(array.child) == .Optional and elem[1] == 0) {
                    arg_idx += 1;
                }
                // Same thing for void
                if (@typeInfo(array.child) == .Void) {
                    arg_idx += 1;
                }
            }

            if (res_idx != res.len) {
                return error.ParseError;
            }

            if (arg_idx >= args.len or !std.mem.eql(u8, args[arg_idx], "]")) {
                return error.ParseError;
            }

            return res;
        },
        .Union => |u| {
            const first = if (args.len != 0) args[0] else return error.MissingArgumentValue;
            const val = if (std.mem.startsWith(u8, first, ".")) first[1..] else first;

            if (args.len < 2 or !std.mem.eql(u8, args[1], "=")) {
                return error.ParseError;
            }

            inline for (u.fields) |field| {
                if (std.mem.eql(u8, val, field.name)) {
                    const payload = try parse_type(args[2..], field.type);
                    return .{@unionInit(arg_type, field.name, payload[0]), 2 + payload[1]};
                }
            }

            return error.ParseError;
        },

        .Struct => @panic("Not supported"),
        else => @panic("not supported"),
    }
}
