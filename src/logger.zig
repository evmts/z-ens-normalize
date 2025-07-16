const std = @import("std");
const builtin = @import("builtin");

pub const LogLevel = enum(u8) {
    off = 0,
    error = 1,
    warn = 2,
    info = 3,
    debug = 4,
    trace = 5,

    pub fn fromString(str: []const u8) LogLevel {
        if (std.mem.eql(u8, str, "off")) return .off;
        if (std.mem.eql(u8, str, "error")) return .error;
        if (std.mem.eql(u8, str, "warn")) return .warn;
        if (std.mem.eql(u8, str, "info")) return .info;
        if (std.mem.eql(u8, str, "debug")) return .debug;
        if (std.mem.eql(u8, str, "trace")) return .trace;
        return .off;
    }
};

var current_log_level: LogLevel = blk: {
    if (builtin.mode == .Debug) {
        break :blk .debug;
    } else {
        break :blk .off;
    }
};

var log_initialized = false;

pub fn init() void {
    if (log_initialized) return;
    
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "ENS_LOG_LEVEL")) |level_str| {
        defer std.heap.page_allocator.free(level_str);
        current_log_level = LogLevel.fromString(level_str);
    } else |_| {}
    
    log_initialized = true;
}

pub fn setLogLevel(level: LogLevel) void {
    current_log_level = level;
}

pub fn getLogLevel() LogLevel {
    if (!log_initialized) init();
    return current_log_level;
}

fn shouldLog(level: LogLevel) bool {
    if (!log_initialized) init();
    return @intFromEnum(level) <= @intFromEnum(current_log_level);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    if (shouldLog(.error)) {
        std.debug.print("[ERROR] " ++ fmt ++ "\n", args);
    }
}

pub fn warn(comptime fmt: []const u8, args: anytype) void {
    if (shouldLog(.warn)) {
        std.debug.print("[WARN]  " ++ fmt ++ "\n", args);
    }
}

pub fn info(comptime fmt: []const u8, args: anytype) void {
    if (shouldLog(.info)) {
        std.debug.print("[INFO]  " ++ fmt ++ "\n", args);
    }
}

pub fn debug(comptime fmt: []const u8, args: anytype) void {
    if (shouldLog(.debug)) {
        std.debug.print("[DEBUG] " ++ fmt ++ "\n", args);
    }
}

pub fn trace(comptime fmt: []const u8, args: anytype) void {
    if (shouldLog(.trace)) {
        std.debug.print("[TRACE] " ++ fmt ++ "\n", args);
    }
}

pub fn hexDump(comptime label: []const u8, data: []const u8) void {
    if (!shouldLog(.trace)) return;
    
    std.debug.print("[TRACE] {s}: ", .{label});
    for (data) |byte| {
        std.debug.print("{x:0>2} ", .{byte});
    }
    std.debug.print("\n", .{});
}

pub fn unicodeDebug(comptime label: []const u8, str: []const u8) void {
    if (!shouldLog(.debug)) return;
    
    std.debug.print("[DEBUG] {s}: \"", .{label});
    var i: usize = 0;
    while (i < str.len) {
        const cp_len = std.unicode.utf8ByteSequenceLength(str[i]) catch 1;
        if (i + cp_len <= str.len) {
            const cp = std.unicode.utf8Decode(str[i..i + cp_len]) catch {
                std.debug.print("<??>", .{});
                i += 1;
                continue;
            };
            if (cp < 128 and std.ascii.isPrint(@intCast(cp))) {
                std.debug.print("{c}", .{@as(u8, @intCast(cp))});
            } else {
                std.debug.print("\\u{{{x}}}", .{cp});
            }
            i += cp_len;
        } else {
            std.debug.print("<??>", .{});
            i += 1;
        }
    }
    std.debug.print("\" (len={})\n", .{str.len});
}

pub fn timing(comptime label: []const u8, start_time: i64) void {
    if (!shouldLog(.debug)) return;
    
    const end_time = std.time.milliTimestamp();
    const duration = end_time - start_time;
    std.debug.print("[DEBUG] {s} took {}ms\n", .{ label, duration });
}

pub const Timer = struct {
    label: []const u8,
    start_time: i64,
    
    pub fn start(label: []const u8) Timer {
        return .{
            .label = label,
            .start_time = std.time.milliTimestamp(),
        };
    }
    
    pub fn stop(self: Timer) void {
        timing(self.label, self.start_time);
    }
};

pub fn enterFn(comptime fn_name: []const u8, args_fmt: []const u8, args: anytype) void {
    if (shouldLog(.trace)) {
        std.debug.print("[TRACE] -> {s}(", .{fn_name});
        std.debug.print(args_fmt, args);
        std.debug.print(")\n", .{});
    }
}

pub fn exitFn(comptime fn_name: []const u8, result_fmt: []const u8, result: anytype) void {
    if (shouldLog(.trace)) {
        std.debug.print("[TRACE] <- {s} returned ", .{fn_name});
        std.debug.print(result_fmt, result);
        std.debug.print("\n", .{});
    }
}

pub fn exitFnVoid(comptime fn_name: []const u8) void {
    if (shouldLog(.trace)) {
        std.debug.print("[TRACE] <- {s} returned\n", .{fn_name});
    }
}

pub fn errTrace(comptime fn_name: []const u8, e: anyerror) void {
    if (shouldLog(.error)) {
        std.debug.print("[ERROR] {s} failed with error: {}\n", .{ fn_name, e });
    }
}