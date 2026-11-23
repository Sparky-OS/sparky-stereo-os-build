// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
// SPDX-License-Identifier: GPL-3.0-or-later
#include <captiond/client.hpp>
#include <captiond/testing/daemon.hpp>
#include <captiond/testing/pipewire.hpp>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <thread>

int main(int argc, char **argv)
{
    if (argc != 2) return 2;
    using namespace std::chrono_literals;
    const std::filesystem::path out(argv[1]);
    std::filesystem::create_directories(out);
    captiond::testing::PrivatePipeWire pipewire;
    if (!pipewire.up()) return 3;
    auto dump = [&](const std::string &name) {
        std::string text;
        const int rc = captiond::testing::run("/usr/bin/pw-dump", {}, pipewire.environment(), &text);
        std::ofstream(out / (name + ".json")) << text;
        return rc == 0;
    };
    if (!dump("before-daemon")) return 4;
    captiond::testing::DaemonOptions options;
    options.arguments = {"--engine", "stub", "--no-gpu", "--source", "sink:captiond-test-sink"};
    options.environment = pipewire.linkable_environment();
    captiond::testing::Daemon daemon(options);
    if (!daemon.ready()) return 5;
    captiond::Client client;
    captiond::Status status;
    nlohmann::json events = nlohmann::json::array();
    client.on_status([&](const captiond::Status &s) { status = s; events.push_back(captiond::status_event(s)); });
    if (!client.connect(daemon.socket_path())) return 6;
    auto wait = [&](auto predicate) {
        return captiond::testing::sleep_until([&] { client.process(); return predicate(); }, 10s);
    };
    if (!wait([&] { return status.state == captiond::DaemonState::Listening; })) return 7;
    if (!pipewire.link_output() || !dump("output-only")) return 8;
    if (!client.set_input("source:captiond-test-source", false, false)) return 9;
    if (!wait([&] { return status.input == "source:captiond-test-source"; })) return 10;
    if (!pipewire.link_input() || !dump("separate-input")) return 11;
    if (!client.set_input("")) return 12;
    if (!wait([&] { return status.input.empty(); })) return 13;
    std::this_thread::sleep_for(500ms);
    if (!dump("input-off")) return 14;
    if (!client.pause()) return 15;
    if (!wait([&] { return status.state == captiond::DaemonState::Paused; })) return 16;
    std::this_thread::sleep_for(500ms);
    if (!dump("paused")) return 17;
    std::ofstream(out / "status.json") << events.dump(2) << '\n';
    client.close();
    return daemon.stop() == 0 ? 0 : 18;
}
