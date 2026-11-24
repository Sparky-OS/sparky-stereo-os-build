// SPDX-License-Identifier: GPL-2.0-or-later
// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
#include <atomic>
#include <thread>
#include <cstdio>
#include <frei0r.hpp>
static std::atomic<bool> paused{false}, entered{false};
class Probe : public frei0r::filter {
 double first=0.25, second=0.75;
public:
 Probe(unsigned w,unsigned) {
  if(w==17) { entered=true;while(paused) std::this_thread::yield(); }
  register_param(first,"first","First independent value");
  register_param(second,"second","Second independent value");
 }
 void update(double,uint32_t*,const uint32_t*) override {}
};
static frei0r::construct<Probe> plugin("Parameter test","Stable metadata","Daniel Campos Ramos",1,0);
int main() {
 f0r_plugin_info_t info{};f0r_get_plugin_info(&info);if(info.num_params!=2)return 2;
 paused=true;f0r_instance_t instance=nullptr;
 std::thread worker([&]{instance=f0r_construct(17,9);});
 while(!entered)std::this_thread::yield();
 f0r_get_plugin_info(&info);const int during=info.num_params;
 paused=false;worker.join();f0r_destruct(instance);
 std::printf("metadata-during-construction expected=2 found=%d\n",during);
 if(during!=2)return 1;
 std::atomic<int> errors{0};
 auto check=[&]{for(int i=0;i<1000;++i){auto *p=f0r_construct(16,9);double value=0.125,got=0;f0r_set_param_value(p,&value,0);f0r_get_param_value(p,&got,0);if(got!=value)++errors;f0r_get_param_value(p,&got,1);if(got!=0.75)++errors;f0r_destruct(p);}};
 std::thread left(check),right(check);left.join();right.join();
 std::printf("two-thousand-independent-instances expected=0 found=%d\n",errors.load());return errors?1:0;
}
