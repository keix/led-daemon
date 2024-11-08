
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

Install libhidapi:

For Ubuntu/Debian:
```bash
sudo apt install libhidapi-dev
```

For Fedora:
```bash
sudo dnf install hidapi-devel
```

For Arch Linux:
```bash
sudo pacman -S hidapi
```

Install Development Tools: Ensure that the C compiler and necessary development libraries are installed:

For Ubuntu/Debian:
```bash

sudo apt install build-essential
```

Building the Project
Clone the repository:

```bash
git clone <repository-url>
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
