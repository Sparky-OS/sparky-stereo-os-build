// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
// SPDX-License-Identifier: GPL-3.0-or-later
// Compile here, but run only from the A10 kit with the explicit recognition guard.
#include <captiond/client.hpp>
#include <captiond/testing/pipewire.hpp>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <thread>
#include <cstdlib>
#include <algorithm>
using namespace std::chrono_literals;
using Clock=std::chrono::steady_clock;
static double seconds(Clock::time_point t) { return std::chrono::duration<double>(t.time_since_epoch()).count(); }
static double ticks(pid_t pid) {
    std::ifstream f("/proc/"+std::to_string(pid)+"/stat");std::string s;std::getline(f,s);
    const auto end=s.rfind(')');if(end==std::string::npos)return -1;
    std::istringstream stream(s.substr(end+2));std::vector<std::string> fields;std::string v;
    while(stream>>v)fields.push_back(v);
    return fields.size()>12?std::stod(fields[11])+std::stod(fields[12]):-1;
}
int main(int argc,char **argv) {
    const char *guard=std::getenv("LC73_A10_RECOGNITION");
    std::ifstream cpu("/proc/cpuinfo");std::string info((std::istreambuf_iterator<char>(cpu)),{});
    if(argc!=6 || !guard || std::string(guard)!="I_choose_model_runs_on_A10" || info.find("A10-9600P")==std::string::npos)return 2;
    const std::string model=argv[1],device=argv[2],expected=argv[3],wav=argv[4];
    const std::filesystem::path out=argv[5];std::filesystem::create_directories(out/"runtime");
    std::filesystem::permissions(out/"runtime",std::filesystem::perms::owner_all);
    captiond::testing::PrivatePipeWire pw;if(!pw.up())return 3;
    std::ofstream(out/"captiond.conf") << "";
    const std::string sock=(out/"runtime/captiond.sock").string();
    auto env=captiond::testing::merged(pw.linkable_environment(),{{"CAPTIOND_SINGLE_INSTANCE","false"},{"CAPTIOND_GPU_DEVICE",device=="cpu"?"0":device},{"CAPTIOND_MODEL_PATH",(out/"no-models").string()},{"XDG_DATA_HOME",(out/"data").string()},{"XDG_DATA_DIRS",(out/"no-models").string()},{"XDG_CONFIG_HOME",(out/"config").string()},{"DBUS_SESSION_BUS_ADDRESS",std::nullopt}});
    std::vector<std::string> args={"--config",(out/"captiond.conf").string(),"--socket",sock,"--engine","whisper","--model",model,"--language","en","--source","sink:captiond-test-sink","--log-level","debug"};
    if(device=="cpu")args.push_back("--no-gpu");
    const int logfd=::open((out/"daemon.log").c_str(),O_WRONLY|O_CREAT|O_TRUNC,0600);
    captiond::testing::Process daemon("/usr/bin/captiond",args,env,logfd);::close(logfd);
    captiond::Client client;captiond::Status status;
    std::ofstream events(out/"events.jsonl"),loads(out/"load.jsonl");
    std::vector<std::pair<double,captiond::Caption>> captions;
    client.on_status([&](const captiond::Status &s){status=s;events<<nlohmann::json{{"received_monotonic_s",seconds(Clock::now())},{"event",captiond::status_event(s)}}.dump()<<std::endl;});
    client.on_caption([&](const captiond::Caption &c){captions.emplace_back(seconds(Clock::now()),c);events<<nlohmann::json{{"received_monotonic_s",captions.back().first},{"event",captiond::caption_event(c)}}.dump()<<std::endl;});
    client.on_error([&](const captiond::Error &e){events<<nlohmann::json{{"error",e.message}}.dump()<<std::endl;});
    const auto load_start=Clock::now();bool connected=false;
    while(Clock::now()-load_start<180s && daemon.running()) {
        if(!connected)connected=client.connect(sock);
        if(connected){client.process();if(status.state==captiond::DaemonState::Listening)break;}
        std::this_thread::sleep_for(20ms);
    }
    nlohmann::json result={{"device_requested",device},{"expected_accelerator",expected},{"status",captiond::status_event(status)},{"load_seconds",seconds(Clock::now())-seconds(load_start)}};
    if(status.state!=captiond::DaemonState::Listening || (device=="cpu"?status.gpu:(!status.gpu || status.accelerator.find(expected)==std::string::npos))) {
        result["error"]="Requested recognizer/device did not become ready; no silent CPU or other-card fallback accepted";
        std::ofstream(out/"result.json")<<result.dump(2);return 4;
    }
    if(!pw.link_output())return 5;
    nlohmann::json trials=nlohmann::json::array();bool all=true;
    for(int trial=0;trial<3;++trial) {
        const auto start=Clock::now();const double cpu_start=ticks(daemon.pid());const std::size_t first=captions.size();
        auto player=pw.play_through_the_speakers(wav);if(!player.started())return 6;
        double end=0,final=0;std::string text;bool behind=false;
        auto next_sample=start;
        while(Clock::now()-start<90s && daemon.running()) {
            client.process();behind=behind||status.behind;
            const auto now=Clock::now();
            if(!end && !player.running())end=seconds(now);
            for(std::size_t n=first;n<captions.size();++n) {
                const auto &c=captions[n].second;std::string lower=c.committed;
                std::transform(lower.begin(),lower.end(),lower.begin(),[](unsigned char x){return std::tolower(x);});
                if(c.final && lower.find("quick brown fox")!=std::string::npos && lower.find("lazy dog")!=std::string::npos) {final=captions[n].first;text=c.committed;break;}
            }
            if(now>=next_sample) {std::ifstream f("/proc/loadavg");std::string l;std::getline(f,l);loads<<nlohmann::json{{"monotonic_s",seconds(now)},{"loadavg",l},{"daemon_cpu_ticks",ticks(daemon.pid())}}.dump()<<std::endl;next_sample=now+100ms;}
            if(end && final)break;
            std::this_thread::sleep_for(10ms);
        }
        const double elapsed=seconds(Clock::now())-seconds(start),used=ticks(daemon.pid())-cpu_start;
        nlohmann::json row={{"trial",trial+1},{"playback_start_monotonic_s",seconds(start)},{"playback_drain_monotonic_s",end},{"final_caption_monotonic_s",final},{"text",text},{"behind_seen",behind},{"daemon_cpu_percent_one_core",100*used/::sysconf(_SC_CLK_TCK)/elapsed},{"passed",end>0&&final>0}};
        if(end && final)row["final_delay_after_wav_end_s"]=final-end;else all=false;
        trials.push_back(row);
        for(int n=0;n<300;++n){client.process();std::this_thread::sleep_for(10ms);}
    }
    result["trials"]=trials;result["metric"]="Final recognized fox phrase arrival minus pw-cat playback drain (end of WAV), sampled at 10 ms; includes live caption settlement, excludes model load. Private null-sink playback, not a physical speaker timing measurement.";
    std::ofstream(out/"result.json")<<result.dump(2)<<'\n';client.close();daemon.terminate();return all?0:7;
}
