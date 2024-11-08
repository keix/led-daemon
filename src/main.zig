const std = @import("std");
const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("stdlib.h");
    @cInclude("hidapi/hidapi.h");
});

const ONE_SECOND = 1000000000;
const STATIC_MODE = 0x01;
const TEMP_THRESHOLD = 30;
const AURA_MAINBOARD_CONTROL_MODE_EFFECT = 0x35;
const AURA_MAINBOARD_CONTROL_MODE_EFFECT_COLOR = 0x36;
const AURA_MAINBOARD_CONTROL_MODE_COMMIT = 0x3F;

pub fn main() !void {
    const first_pid = c.fork();
    if (first_pid < 0) {
        std.debug.print("Failed to fork\n", .{});
        c.exit(1);
    }

    if (first_pid == 0) {
        if (c.setsid() < 0) {
            std.debug.print("Failed to create session\n", .{});
            c.exit(1);
        }

        const second_pid = c.fork();
        if (second_pid < 0) {
            std.debug.print("Failed to fork again\n", .{});
            c.exit(1);
        }

        if (second_pid == 0) {
            while (true) {
                const color = try getColor();
                _ = try updateLedColor(color.red, color.green, color.blue);
                std.debug.print("Daemon is running...\n", .{});
                std.time.sleep(ONE_SECOND);
            }
        } else {
            c._exit(0);
        }
    } else {
        c._exit(0);
    }
}

pub fn getColor() !Color {
    const stdout = std.io.getStdOut().writer();

    const file_name = "/sys/class/thermal/thermal_zone0/temp";
    const file = try std.fs.cwd().openFile(file_name, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    var reader = std.io.bufferedReader(file.reader());
    var instream = reader.reader();

    const allocator = std.heap.page_allocator;
    const contents = try instream.readAllAlloc(allocator, file_size);
    defer allocator.free(contents);

    const temp_milli = try parseTemperature(contents);
    const temp_celsius = @divTrunc(temp_milli, 1000);
    try stdout.print("CPU Temperature: {d}°C\n", .{temp_celsius});

    const rgb = getTemperatureColor(temp_celsius);
    try stdout.print("RGB Color: ({d}, {d}, {d})\n", .{ rgb.red, rgb.green, rgb.blue });

    return rgb;
}

fn parseTemperature(contents: []const u8) !i32 {
    const trimmed = std.mem.trimRight(u8, contents, " \t\n\r");
    return std.fmt.parseInt(i32, trimmed, 10);
}

fn getTemperatureColor(temp: i32) Color {
    if (temp > TEMP_THRESHOLD) {
        return Color{
            .red = 255,
            .green = 0,
            .blue = 0,
        };
    } else {
        return Color{
            .red = 0,
            .green = 0,
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
    try checkError(c.hid_init());
    defer _ = c.hid_exit();

    const dev: ?*c.hid_device = c.hid_open(0x0B05, 0x19AF, null);
    if (dev == null) {
        std.debug.print("Failed to open ASUS Aura Mainboard\n", .{});
        return error.DeviceNotFound;
    }
    defer c.hid_close(dev);

    std.debug.print("Device opened successfully\n", .{});
    try setMode(dev, 0, STATIC_MODE, red, green, blue);
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
    std.debug.print("Effect set to mode {d} on channel {d}\n", .{ mode, channel });
}

fn sendColor(dev: ?*c.hid_device, start_led: u8, led_count: u8, led_data: *[3]u8, shutdown_effect: bool) !void {
    var usb_buf: [65]u8 = [_]u8{0} ** 65;

    const mask: u16 = 0xFFFF;
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
    std.debug.print("Color data sent for {d} LEDs starting at {d}\n", .{ led_count, start_led });
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
    if (mode == STATIC_MODE) {
        var led_data: [3]u8 = [_]u8{ red, green, blue };
        try sendColor(dev, channel, 1, &led_data, shutdown_effect);
    }
}

fn checkError(result: c_int) !void {
    if (result < 0) {
        return error.USBError;
    }
}
