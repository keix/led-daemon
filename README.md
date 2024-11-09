
# LED Daemon - ASUS Aura RGB Controller

This project is a Zig-based daemon for controlling ASUS Aura RGB lighting. It dynamically adjusts the LED colors based on the system's CPU temperature, utilizing the hidapi library to communicate with the ASUS Aura Mainboard's USB HID interface.

## Features
Forks into a daemon process to run continuously in the background.
Monitors CPU temperature using system thermal zone data.
Adjusts LED colors based on temperature:
Blue for temperatures below the threshold.
Red for temperatures above the threshold.
Communicates with ASUS Aura devices via hidapi.

## Requirements
### Hardware
    - ASUS Aura-compatible mainboard with USB HID interface.
### Software
    - Operating System: Linux
### Dependencies:
    - Zig (latest stable version)
    - libhidapi (HID API library for USB communication)
    - C standard library (libc)
    - LLVM (for Zig compilation)
### Installation
#### Prerequisites
Install Zig: Follow the official Zig installation guide.

- https://github.com/ziglang/zig/tree/master?tab=readme-ov-file#installation

#### Building the Project
Clone the repository:

```bash
git clone git@github.com:keix/led-daemon.git
cd led-daemon
```

Build the project using Zig:

```bash
zig build
```

The compiled executable will be located at zig-out/bin/led-daemon.

### Usage
Run the daemon:

```bash
./zig-out/bin/led-daemon
```

Stop the daemon:

```bash
kill -9 $(cat led-daemon.pid) && rm led-daemon.pid
```

The daemon will:

- Fork into the background.
- Continuously monitor the CPU temperature.
- Update the LED colors accordingly.

### Code Structure
- main.zig: Entry point of the daemon, containing the logic for forking processes and managing the daemon lifecycle.
- Temperature Monitoring:
    - Reads CPU temperature from /sys/class/thermal/thermal_zone0/temp.
    - Parses and converts the temperature to Celsius.
- RGB Control:
    - Sends USB HID commands to the ASUS Aura device to update LED colors based on the CPU temperature.
    - Supports static color mode.

### Configuration
- Temperature Threshold: Adjust the TEMP_THRESHOLD constant in main.zig to set the temperature threshold for changing LED colors.
- Default Colors: Modify the getTemperatureColor function to customize the RGB values for different temperature ranges.
