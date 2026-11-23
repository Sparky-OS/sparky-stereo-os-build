# Foottroller Hub for Linux

The Hub reads a Crampon in Dev mode. It sends movement and foot state to games that use the Foottroller UDP integration and exposes a virtual gamepad for ordinary gamepad bindings.

Connect the Crampon and enable Dev mode using the rightmost button on the control box. Run `foottroller-hub` to see the Linux joystick names and paths. Then start it with `foottroller-hub --device /dev/input/jsN` using the Crampon's path, or put that path in `device` in `/etc/foottroller-hub.conf`. Run as the person playing, with read access to that joystick and write access to `/dev/uinput`. Press Ctrl+C to stop. The virtual device is named **Foottroller Hub Gamepad**.

The one settings file holds the joystick ordinals, per-axis inversion and normalized dead zones. You can use a copy with `--config FILE`. The shipped mapping follows X. Tian's Linux joystick plugin. The maker's HID-side axis labels and the Linux joystick ordinals need comparison on a real Crampon. The Hub checks the required axis and button counts and consumes the kernel's initial state when it opens. Firmware that keeps the same counts and initial state in another mode would need an additional mode signal.

The game integration listens for the Hub on UDP 45041. The Hub accepts connections on any local IPv4 address by default so the Unity example can find it at the PC's LAN address. Set `bind_address` to the one local address the game can reach. Use this UDP protocol on a trusted network.

`--replay FILE_OR_FIFO` explicitly accepts the Linux joystick event layout for bench tests. Start the recording with all configured axes and buttons marked `JS_EVENT_INIT`. This route still creates the real virtual gamepad unless the system calls are intercepted by the test. Leave the replay FIFO open until the observer has read the events.

Sources: [the maker's Dev mode instructions](https://foottroller.com/instructions), [Linux joystick mapping](https://github.com/smoothmover/IsaacTeleop-Foottroller/blob/f447a3f2f16ff34b996b362c8b4efc0d4fb7f288/src/plugins/foottroller/README.md), [Unity client](https://github.com/smoothmover/foottrollersupport/blob/f9182997b60b5012ca2b0dd50bb66221bc9b89b8/Unity/FoottrollerNet.cs), [Linux joystick API](https://docs.kernel.org/input/joydev/joystick-api.html#event-reading), [Linux gamepad specification](https://docs.kernel.org/input/gamepad.html#detection), and [uinput](https://docs.kernel.org/input/uinput.html#interface).
