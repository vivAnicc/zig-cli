const std = @import("std");
const run_command = @import("root.zig").run;

pub fn ParseResult(comptime namespace: type) type {
    return union(enum) {
        Command: Commands(namespace),
        Help: HelpCommand(namespace),
        Error: CommandError(namespace),

        pub fn run(self: @This()) void {
            switch (self) {
                .Command => |command| run_command(command),
                .Help => |help| help.print(),
                .Error => |err| {
                    std.debug.print("[ERROR] {}\n", .{err});
                    switch (err.err) {
                        .UnknownCommand => print_help(true, err.exe, Commands(namespace)),
                        .MissingCommand => print_help(true, err.exe, Commands(namespace)),
                        .TooManyArguments => |e| print_cmd_help(true, err.exe, e.cmd),
                        .InvalidArgument => |e| print_cmd_help(true, err.exe, e.cmd),
                        .InvalidArgumentType => |e| print_cmd_help(true, err.exe, e.cmd),
                        .MissingArgument => |e| print_cmd_help(true, err.exe, e.cmd),
                    }
                },
            }
        }
    };
}

pub fn HelpCommand(comptime namespace: type) type {
    return struct {
        args: []const []const u8,
        command: ?Commands(namespace),

        pub fn print(self: @This()) void {
            if (self.command) |cmd| {
                print_cmd_help(false, self.args[0], cmd);
            } else {
                print_help(false, self.args[0], @TypeOf(self.command.?));
            }
        }
    };
}

pub fn print_cmd_help(err: bool, exe: []const u8, command: anytype) void {
    if (err) {
        std.debug.print("Incorrect usage. Correct usage: {s} {s} [arguments...]\n", .{exe, cmd_name(command)});
    } else {
        std.debug.print("Usage: {s} {s} [arguments...]\n", .{exe, cmd_name(command)});
    }

    std.debug.print("Info:    - {s} -> {s}\n", .{cmd_name(command), cmd_desc(command)});
}

pub fn print_help(err: bool, exe: []const u8, comptime commands: type) void {
    if (err) {
        std.debug.print("Incorrect usage. Correct usage: {s} <command> [arguments...]\n", .{exe});
    } else {
        std.debug.print("Usage: {s} <command> [arguments...]\n", .{exe});
    }

    std.debug.print("Available commands:\n", .{});

    inline for (@typeInfo(commands).Union.fields) |field| {
        const payload_type = field.type;

        std.debug.print("   - {s} -> {s}\n", .{payload_type.name, payload_type.desc});
    }

    std.debug.print("   - help -> Print this help message\n", .{});
}

pub fn cmd_get(command: anytype, comptime name: []const u8) []const u8 {
    const T = @TypeOf(command);

    const tag = std.meta.activeTag(command);
    inline for (@typeInfo(T).Union.fields) |curr| {
        if (tag == std.meta.stringToEnum(std.meta.Tag(T), curr.name)) {
            const data = @field(command, curr.name);
            return @field(@TypeOf(data), name);
        }
    }

    unreachable;
}

pub fn cmd_name(command: anytype) []const u8 {
    return cmd_get(command, "name");
}

pub fn cmd_desc(command: anytype) []const u8 {
    return cmd_get(command, "desc");
}

pub fn CommandErrorUnion(namespace: type) type {
    return union(enum) {
        TooManyArguments: TooManyArgumentsError(namespace),
        InvalidArgument: InvalidArgumentError(namespace),
        InvalidArgumentType: InvalidArgumentTypeError(namespace),
        MissingArgument: MissingArgumentError(namespace),
        UnknownCommand: []const u8,
        MissingCommand,

        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;

            switch (self) {
                .TooManyArguments => |err| try writer.print("{}", .{err}),
                .InvalidArgument => |err| try writer.print("{}", .{err}),
                .InvalidArgumentType => |err| try writer.print("{}", .{err}),
                .MissingArgument => |err| try writer.print("{}", .{err}),
                .UnknownCommand => |err| try writer.print("Unknown Command: '{s}'", .{err}),
                .MissingCommand => try writer.print("Missing Command", .{}),
            }
        }
    };
}

pub fn CommandError(namespace: type) type {
    return struct {
        exe: []const u8,
        err: CommandErrorUnion(namespace),
        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            try writer.print("{}", .{self.err});
        }
    };
}

pub fn MissingArgumentError(namespace: type) type {
    return struct {
        cmd: Commands(namespace),
        arg: []const u8,

        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            try writer.print("Missing Argument '{s}' required by Command '{s}'", .{self.arg, cmd_name(self.cmd)});
        }
    };
}

pub fn InvalidArgumentTypeError(namespace: type) type {
    return struct {
        cmd: Commands(namespace),
        arg: []const u8,

        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            try writer.print("Invalid Type for Argument '{s}' in Command '{s}'", .{self.arg, cmd_name(self.cmd)});
        }
    };
}

pub fn InvalidArgumentError(namespace: type) type {
    return struct {
        cmd: Commands(namespace),
        arg: []const u8,

        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;
            try writer.print("Invalid Argument for Command '{s}': '{s}'", .{cmd_name(self.cmd), self.arg});
        }
    };
}

pub fn TooManyArgumentsError(namespace: type) type {
    return struct {
        cmd: Commands(namespace),
        args: []const []const u8,

        pub fn format(
            self: @This(),
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = fmt;
            _ = options;

            try writer.print("Too Many Arguments for Command '{s}'.\nExcess: '", .{cmd_name(self.cmd)});
            for (self.args, 0..) |arg, i| {
                try writer.print("{s}", .{arg});
                if (i != self.args.len - 1) {
                    try writer.print(" ", .{});
                }
            }

            try writer.print("'", .{});
        }
    };
}

pub fn Commands(comptime namespace: type) type {
    comptime {
        const decls = std.meta.declarations(namespace);
        var types_array: [decls.len]type = undefined;

        var i = 0;
        for (decls) |decl_info| {
            const decl = @field(namespace, decl_info.name);
            if (@TypeOf(decl) != type) {
                continue;
            }

            FnCommand(decl) catch continue;
            types_array[i] = decl;
            i += 1;
        }

        const types = types_array[0..i];

        var enum_fields: [i]std.builtin.Type.EnumField = undefined;
        for (types, 0..) |command, idx| {
            enum_fields[idx] = .{
                .name = command.name,
                .value = idx,
            };
        }

        const enum_info = std.builtin.Type{ .Enum = .{
            .decls = &.{},
            .fields = &enum_fields,
            .tag_type = usize,
            .is_exhaustive = true,
        } };

        var union_fields: [types.len]std.builtin.Type.UnionField = undefined;
        for (types, 0..) |command, idx| {
            union_fields[idx] = .{
                .name = command.name,
                .type = Command(command.name, command.desc, command.args, command.run),
                .alignment = @alignOf(command),
            };
        }

        const union_info = std.builtin.Type{ .Union = .{
            .decls = &.{},
            .tag_type = @Type(enum_info),
            .fields = &union_fields,
            .layout = .auto,
        } };

        return @Type(union_info);
    }
}

fn Command(comptime _name: []const u8, comptime _desc: []const u8, comptime _params: []const []const u8, _func: anytype) type {
    const func_type = @TypeOf(_func);
    std.debug.assert(@typeInfo(func_type) == .Fn);

    return struct {
        pub const name = _name;
        pub const desc = _desc;
        pub const func = _func;
        pub const params = _params;

        args: std.meta.ArgsTuple(func_type),

        pub fn run(self: @This()) void {
            @call(.auto, @This().func, self.args);
        }
    };
}

const CommandCreationError = error {
    NameNotPresent,
    NameWrongType,

    DescNotPresent,
    DescWrongType,

    ArgsNotPresent,
    ArgsWrongType,

    FnNotPresent,
    FnWrongType,
};

pub fn FnCommand(comptime command: type) CommandCreationError!void {
    var fn_opt: ?[]const u8 = null;
    var name_opt: ?[]const u8 = null;
    var desc_opt: ?[]const u8 = null;
    var args_opt: ?[]const []const u8 = null;

    const decls = std.meta.declarations(command);
    inline for (decls) |decl| {
       if (std.mem.eql(u8, decl.name, "run")) {
            fn_opt = decl.name;
        } else if (std.mem.eql(u8, decl.name, "name")) {
            const name_lit = @field(command, decl.name);
            if (from_string_lit(name_lit)) |name| {
                name_opt = name;
            } else {
                return error.NameWrongType;
            }
        } else if (std.mem.eql(u8, decl.name, "desc")) {
            const desc_lit = @field(command, decl.name);
            if (from_string_lit(desc_lit)) |desc| {
                desc_opt = desc;
            } else {
                return error.DescWrongType;
            }
        } else if (std.mem.eql(u8, decl.name, "args")) {
            const desc_lit = @field(command, decl.name);
            if (from_string_lit_array(desc_lit)) |args| {
                args_opt = args;
            } else {
                return error.ArgsWrongType;
            }
        }
    }

    if (name_opt == null) {
        return error.NameNotPresent;
    }
    if (desc_opt == null) {
        return error.DescNotPresent;
    }
    if (args_opt == null) {
        return error.ArgsNotPresent;
    }

    const fn_name = fn_opt orelse return error.FnNotPresent;
    const fn_field = @typeInfo(@TypeOf(@field(command, fn_name)));
    if (fn_field != .Fn) {
        return error.FnWrongType;
    }

    // std.debug.assert(fn_field.Fn.params.len == 0);
    std.debug.assert(fn_field.Fn.return_type == void);
}

fn from_string_lit(string: anytype) ?[]const u8 {
    const Type = @TypeOf(string);
    const info = @typeInfo(Type);

    if (info == .Pointer) {
        const ptr = info.Pointer;
        if (ptr.is_const) {
            const child = @typeInfo(ptr.child);
            if (child == .Array) {
                const array = child.Array;
                if (array.child == u8) {
                    const sentinel: *const u8 = @ptrCast(@alignCast(array.sentinel.?));
                    if (sentinel.* == 0) {
                        return @as([]const u8, string);
                    }
                }
            }
        }
    }

    return null;
}

fn from_string_lit_array(array: anytype) ?[]const []const u8 {
    const Type = @TypeOf(array);
    const info = @typeInfo(Type);

    if (info == .Pointer) {
        const ptr = info.Pointer;
        if (ptr.is_const) {
            const child = @typeInfo(ptr.child);
            if (child == .Struct) {
                const s = child.Struct;
                if (s.is_tuple) {
                    const struct_fields = s.fields;

                    for (struct_fields) |field| {
                        if (!field.is_comptime) {
                            return null;
                        }

                        if (field.default_value) |default| {
                            const default_ptr: *const field.type = @ptrCast(@alignCast(default));
                            if (from_string_lit(default_ptr.*) == null) {
                                return null;
                            }
                        } else return null;
                    }

                    return @as([]const []const u8, array);
                }
            }
        }
    }

    return null;
}
