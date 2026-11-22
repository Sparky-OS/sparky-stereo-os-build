// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
// SPDX-License-Identifier: GPL-3.0-or-later
#include <captiond/protocol.hpp>
#include <captiond/testing/pipewire.hpp>
#include <captiond/testing/stand_in.hpp>
#include <chrono>
#include <fstream>
#include <iostream>
#include <thread>

int main(int argc, char **argv)
{
    if (argc != 4) {
        std::cerr << "usage: stand-in SOCKET SPEECH_WAV OUTPUT_JSON\n";
        return 2;
    }
    using namespace std::chrono_literals;
    captiond::testing::PrivatePipeWire pipewire;
    if (!pipewire.up()) return 3;
    captiond::testing::StandInDaemon daemon(argv[1]);
    if (!daemon.listening()) return 4;
    captiond::Status status;
    status.state = captiond::DaemonState::Listening;
    status.engine = "stub";
    status.language = "en";
    status.source = "sink:captiond-test-sink";
    status.live = true;
    daemon.on_connect({captiond::hello_event().dump(), captiond::status_event(status).dump()});
    std::ofstream(argv[3]) << nlohmann::json{{"recognition", "synthetic: upstream StandInDaemon"},
                                          {"socket", argv[1]}, {"pipewire_runtime", pipewire.dir()},
                                          {"model_loaded", false}}.dump(2) << '\n';
    if (!daemon.accept_one(60s)) return 5;
    auto player = pipewire.play_through_the_speakers(argv[2]);
    if (!player.started()) return 6;
    // Known text is fed through the real protocol. This is not speech recognition.
    for (int i = 0; i < 40; ++i) {
        captiond::Caption caption;
        caption.id = static_cast<unsigned>(i + 1);
        caption.committed = "The quick brown fox jumps over the lazy dog.";
        caption.lang = "en";
        caption.final = true;
        caption.t0 = std::chrono::milliseconds(i * 3000);
        caption.t1 = caption.t0 + 2000ms;
        daemon.send(captiond::caption_event(caption));
        std::cout << captiond::caption_event(caption).dump() << std::endl;
        std::this_thread::sleep_for(3s);
    }
}
