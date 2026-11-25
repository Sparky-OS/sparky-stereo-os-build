# video-wallpaper: org.kde.video for the edition

The recipe of `qml-module-org-kde-video-wallpaper`: the video wallpaper and lock screen plugin `org.kde.video` by Jeromy Streets, his own Plasma 6 port as merged in [Sparky-OS/org.kde.video](https://github.com/Sparky-OS/org.kde.video) (branch `stereo3d`, pull request 26, commit `15035dc949a0105b4d70a4abf14c19af564154a5`), packaged unchanged.

- `make-source.sh CLONE WORK` makes the source from a clone and refuses any other commit, tree or archive (the three pins are in the script). No patch is applied: a fault found in the plugin is written up for a pull request in its repository.
- The package keeps the name of SparkyLinux's package of the Plasma 5 version (0.1.0), so a machine that has it gets this one by a plain upgrade.
- Build: `release/build-dh-lean.sh WORK source 2.0.0~git20261029.15035dc9-1+lc1 REPO`.
