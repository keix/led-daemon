const std = @import("std");
const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("stdlib.h");
    @cInclude("fcntl.h");
    @cInclude("hidapi/hidapi.h");
});

const SUCCESS = 0;
const ERROR = 1;

const VENDOR_ID = 0x0B05;
const PRODUCT_ID = 0x19AF;

const AURA_MAINBOARD_CONTROL_MODE_EFFECT = 0x35;
const AURA_MAINBOARD_CONTROL_MODE_EFFECT_COLOR = 0x36;
const AURA_MAINBOARD_CONTROL_MODE_COMMIT = 0x3F;

const PID_LOG = "/tmp/led-daemon.pid";
const DEV_NULL = "/dev/null";
const THERMAL_ZONE = "/sys/class/thermal/thermal_zone2/temp";
const DIRECT_MODE = 0x01;

const TEMP_THRESHOLD = 35;
const CELSIUS = 1000;
const ONE_SECOND = 1000000000;

pub fn daemonize() !void {
    const first_pid = c.fork();
    if (first_pid < 0) {
        std.debug.print("First fork failed:\n", .{});
        c.exit(ERROR);
    }
    if (first_pid > 0) c._exit(SUCCESS);

    if (c.setsid() < 0) {
        std.debug.print("Failed to create new session:\n", .{});
        c.exit(ERROR);
    }

    const second_pid = c.fork();
    if (second_pid < 0) {
        std.debug.print("Second fork failed:\n", .{});
        c.exit(ERROR);
    }
    if (second_pid > 0) c._exit(SUCCESS);

    if (c.chdir("/") < 0) {
        std.debug.print("Failed to change directory to /:\n", .{});
        c.exit(ERROR);
    }

    _ = try setRootDirectory();
    _ = try writePid();
    _ = try redirectStdoutToNull();
}

pub fn writePid() !void {
    const pid = c.getpid();

    var file = try std.fs.cwd().createFile(PID_LOG, .{ .truncate = true });
    defer file.close();
    var buffer: [32]u8 = undefined;
    const written = try std.fmt.bufPrint(&buffer, "{d}\n", .{pid});
    _ = try file.writeAll(written);
}

pub fn setRootDirectory() !void {
    if (c.chdir("/") < 0) {
        std.debug.print("Failed to change directory to /:\n", .{});
        c.exit(ERROR);
    }
}

pub fn main() !void {
    _ = try daemonize();

    try checkError(c.hid_init());
    defer _ = c.hid_exit();

    while (true) {
        const color = try getColor();
        _ = try updateLedColor(color.red, color.green, color.blue);
        std.debug.print("Daemon is running...\n", .{});
        std.time.sleep(ONE_SECOND);
    }
}

fn redirectStdoutToNull() !void {
    const fd = c.open(DEV_NULL, c.O_WRONLY);
    if (fd < 0) return error.OpenFailed;
    defer _ = c.close(fd);

    if (c.dup2(fd, 0) < 0) return error.Dup2Failed;
    if (c.dup2(fd, 1) < 0) return error.Dup2Failed;
    if (c.dup2(fd, 2) < 0) return error.Dup2Failed;
}

pub fn getColor() !Color {
    const stdout = std.io.getStdOut().writer();
    const file = try std.fs.cwd().openFile(THERMAL_ZONE, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    var reader = std.io.bufferedReader(file.reader());
    var instream = reader.reader();

    const allocator = std.heap.page_allocator;
    const contents = try instream.readAllAlloc(allocator, file_size);
    defer allocator.free(contents);

    const temp_milli = try parseTemperature(contents);
    const temp_celsius = @divTrunc(temp_milli, CELSIUS);
    try stdout.print("CPU Temperature: {d}°C\n", .{temp_celsius});

    const rgb = getTemperatureColor(temp_celsius);
    _ = try stdout.print("RGB Color: ({d}, {d}, {d})\n", .{ rgb.red, rgb.green, rgb.blue });

    return rgb;
}

fn parseTemperature(contents: []const u8) !i32 {
    const trimmed = std.mem.trimRight(u8, contents, " \t\n\r");
    return std.fmt.parseInt(i32, trimmed, 10);
}

fn getTemperatureColor(temp: i32) Color {
    if (temp >= TEMP_THRESHOLD) {
        return Color{
            .red = 255,
            .green = 0,
            .blue = 10,
        };
    } else {
        return Color{
            .red = 210,
            .green = 190,
            .blue = 210,
        };
    }
}

const Color = struct {
    red: u8,
    green: u8,
    blue: u8,
};

pub fn updateLedColor(red: u8, green: u8, blue: u8) !void {
    const dev: ?*c.hid_device = c.hid_open(VENDOR_ID, PRODUCT_ID, null);
    if (dev == null) {
        std.debug.print("Failed to open ASUS Aura Mainboard\n", .{});
        return error.DeviceNotFound;
    }
    defer c.hid_close(dev);

    std.debug.print("Device opened successfully\n", .{});
    try setMode(dev, 0, 0x01, red, green, blue);
    try sendCommit(dev);
}

fn sendEffect(dev: ?*c.hid_device, channel: u8, mode: u8, shutdown_effect: bool) !void {
    var usb_buf: [65]u8 = [_]u8{0} ** 65;

    usb_buf[0] = 0xEC;
    usb_buf[1] = AURA_MAINBOARD_CONTROL_MODE_EFFECT;
    usb_buf[2] = channel;
    usb_buf[4] = if (shutdown_effect) 0x01 else 0x00;
    usb_buf[5] = mode;

    const result = c.hid_write(dev, &usb_buf, usb_buf.len);
    try checkError(result);
    _ = std.debug.print("Effect set to mode {d} on channel {d}\n", .{ mode, channel });
}

fn sendColor(dev: ?*c.hid_device, start_led: u8, led_count: u8, led_data: *[3]u8, shutdown_effect: bool) !void {
    const mask: u16 = 0x7FFF;
    var usb_buf: [65]u8 = [_]u8{0} ** 65;

    usb_buf[0] = 0xEC;
    usb_buf[1] = AURA_MAINBOARD_CONTROL_MODE_EFFECT_COLOR;
    usb_buf[2] = mask >> 8;
    usb_buf[3] = mask & 0xFF;
    usb_buf[4] = if (shutdown_effect) 0x01 else 0x00;

    for (0..led_count * 3) |i| {
        usb_buf[5 + i] = @intCast(led_data[i % 3]);
    }

    const result = c.hid_write(dev, &usb_buf, usb_buf.len);
    try checkError(result);
    _ = std.debug.print("Color data sent for {d} LEDs starting at {d}\n", .{ led_count, start_led });
}

fn sendCommit(dev: ?*c.hid_device) !void {
    var usb_buf: [65]u8 = [_]u8{0} ** 65;

    usb_buf[0] = 0xEC;
    usb_buf[1] = AURA_MAINBOARD_CONTROL_MODE_COMMIT;
    usb_buf[2] = 0x55;

    const result = c.hid_write(dev, &usb_buf, usb_buf.len);
    try checkError(result);
    std.debug.print("Commit successful\n", .{});
}

fn setMode(dev: ?*c.hid_device, channel: u8, mode: u8, red: u8, green: u8, blue: u8) !void {
    const shutdown_effect = false;
    try sendEffect(dev, channel, mode, shutdown_effect);

    if (mode == DIRECT_MODE) {
        var led_data: [3]u8 = [_]u8{ red, green, blue };
        try sendColor(dev, channel, 1, &led_data, shutdown_effect);
    }
}

fn checkError(result: c_int) !void {
    if (result < 0) {
        return error.USBError;
    }
}
