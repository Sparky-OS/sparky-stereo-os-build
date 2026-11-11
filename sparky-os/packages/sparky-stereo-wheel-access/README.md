sparky-stereo-wheel-access
Gives the games group the controls a wheel driver creates root-only, and says when it cannot.

The udev rules of new-lg4ff-dkms, hid-tmff2-dkms and hid-fanatecff-dkms run /usr/lib/udev/sparky-stereo-wheel-access with the device's sysfs folder and the controls of the driver.
Before 0.1.0 each rule ran `chown -f ... || true`, so a control that was there and could not be changed looked like one that was never there.

Use:
-------------
Nothing to run.
A control the wheel's model does not have is skipped (the drivers create different files for different models).
A control that is there and cannot be changed (a read-only /sys, a missing games group) is kept by sparky-stereo-problems for that wheel and shown by the session's notifier, with Repair, which tries again.
The problem is cleared when the same wheel's controls are set up again, or by Repair when the wheel has been unplugged.
The helper exits 1 then, which udev logs with the message.

Dependencies:
-------------
sparky-stereo-problems >= 0.1.2
udev
