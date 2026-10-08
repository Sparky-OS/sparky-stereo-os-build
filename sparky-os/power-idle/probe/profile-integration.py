#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later

import os
import pathlib
import subprocess
import unittest

import dbus
from gi.repository import GLib
import integration_test as upstream


class EditionProfiles(upstream.Tests):
    def test_modes(self):
        work = pathlib.Path(os.environ["POWER_IDLE_WORK"])
        self.create_amd_apu()
        policy = pathlib.Path(self.testbed.get_root_dir()) / "sys/devices/system/cpu/cpufreq/policy0"
        policy.mkdir(parents=True)
        governor = policy / "scaling_governor"
        epp = policy / "energy_performance_preference"
        governor.write_text("powersave\n")
        epp.write_text("performance\n")
        pstate = pathlib.Path(self.testbed.get_root_dir()) / "sys/devices/system/cpu/amd_pstate"
        pstate.mkdir()
        (pstate / "status").write_text("active\n")
        dpm_attr = "device/power_dpm_force_performance_level"
        card = self.testbed.add_device("drm", "card0", None, [dpm_attr, "auto\n"], ["DEVTYPE", "drm_minor"])
        panel_attr = "amdgpu/panel_power_savings"
        panel = self.testbed.add_device("drm", "card0-eDP", None,
                                       ["status", "connected\n", panel_attr, "0"], ["DEVTYPE", "drm_connector"])
        _, upower, _ = self.start_dbus_template("upower", {"DaemonVersion": "0.99", "OnBattery": False})
        upower.SetDeviceProperties("/org/freedesktop/UPower/devices/DisplayDevice",
                                  {"Percentage": dbus.Double(15, variant_level=1)})
        self.start_daemon()
        actions = {action["Name"]: action["Enabled"] for action in self.get_dbus_property("ActionsInfo")}
        self.assertIs(actions["amdgpu_dpm"], False)
        self.assertIs(actions["amdgpu_panel_power"], False)
        hardware_work = work / "profile-hardware-work"
        hardware_work.mkdir(exist_ok=True)
        setup_env = os.environ.copy()
        setup_env["WORK"] = str(hardware_work)
        setup_env["PATH"] = str(work / "ppd-runtime/src") + ":" + setup_env["PATH"]
        setup = subprocess.run(["/bin/bash", "-ec", 'source "$POWER_IDLE_HARDWARE_ACTIONS"; setup_amdgpu amdgpu_dpm amdgpu_panel_power'],
                               env=setup_env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True)
        print(setup.stdout, flush=True)
        actions = {action["Name"]: action["Enabled"] for action in self.get_dbus_property("ActionsInfo")}
        self.assertIs(actions["amdgpu_dpm"], True)
        self.assertIs(actions["amdgpu_panel_power"], True)

        config_home = work / "profile-config-home"
        config_home.mkdir(exist_ok=True)
        env = os.environ.copy()
        env["XDG_CONFIG_HOME"] = str(config_home)
        env["XDG_CONFIG_DIRS"] = os.environ["POWER_IDLE_PROFILE_DEFAULTS"]

        def apply(profile, expected, expected_epp, expected_governor, dpm, savings):
            result = subprocess.run([str(work / "build/settings-probe"), "--apply-profile", profile],
                                    env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=True)
            print(result.stdout.strip(), flush=True)
            self.assert_eventually(lambda: self.get_dbus_property("ActiveProfile") == expected)
            self.assert_file_eventually_contains(str(epp), expected_epp)
            self.assert_file_eventually_contains(str(governor), expected_governor)
            self.assert_sysfs_attr_eventually_is(card, dpm_attr, dpm)
            self.assert_sysfs_attr_eventually_is(panel, panel_attr, savings)
            print(f"PASS {profile}: profile={expected}, EPP={expected_epp}, governor={expected_governor}, "
                  f"GPU={dpm}, panel={savings}", flush=True)

        apply("AC", "performance", "performance", "performance", "auto", "0")
        upower.Set("org.freedesktop.UPower", "OnBattery", True)
        apply("Battery", "balanced", "balance_power", "powersave", "auto", "1")
        apply("LowBattery", "power-saver", "power", "powersave", "low", "3")
        apply("Battery", "balanced", "balance_power", "powersave", "auto", "1")
        self.set_dbus_property("ActiveProfile", GLib.Variant.new_string("power-saver"))
        self.assert_file_eventually_contains(str(epp), "power")
        self.assert_sysfs_attr_eventually_is(card, dpm_attr, "low")
        self.assert_sysfs_attr_eventually_is(panel, panel_attr, "3")
        print("PASS user's power-saver choice applies PPD GPU savings", flush=True)
        upower.Set("org.freedesktop.UPower", "OnBattery", False)
        apply("AC", "performance", "performance", "performance", "auto", "0")


if __name__ == "__main__":
    assert pathlib.Path("/.dockerenv").exists(), "Run in Docker only"
    unittest.main()
