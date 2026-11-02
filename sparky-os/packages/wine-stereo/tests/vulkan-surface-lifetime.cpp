#include "wsi/wsi_wine_stereo.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>

dxvk::Logger dxvk::Logger::s_instance("surface-lifetime.log");
static VkInstance instance;
static PFN_vkCreateWin32SurfaceKHR create_surface;
static PFN_vkDestroySurfaceKHR destroy_surface;
static HWND child, owner_a, owner_b;
static HANDLE ready, release_surface, done;
static LONG failures;
static int iterations=1;
static long long ticks() { LARGE_INTEGER value; QueryPerformanceCounter(&value); return value.QuadPart; }
static void require(bool value, const char *what) { if(!value){std::printf("FAIL %s error=%lu\n",what,GetLastError());std::fflush(stdout);ExitProcess(2);} }
static void pump() { MSG m;while(PeekMessageW(&m,nullptr,0,0,PM_REMOVE)){TranslateMessage(&m);DispatchMessageW(&m);} }
static void wait_event(HANDLE event) {
    DWORD start=GetTickCount();
    while(WaitForSingleObject(event,0)!=WAIT_OBJECT_0){require(GetTickCount()-start<15000,"event timeout");MsgWaitForMultipleObjectsEx(1,&event,10,QS_ALLINPUT,MWMO_INPUTAVAILABLE);pump();}
}
static DWORD WINAPI read_reply(void *) { char line[32];return std::fgets(line,sizeof(line),stdin)?0:91; }
static void capture(int phase) {
    std::printf("phase=%d logical=320x200 frame=ready\n",phase);std::fflush(stdout);
    HANDLE thread=CreateThread(nullptr,0,read_reply,nullptr,0,nullptr);require(thread!=nullptr,"reader");wait_event(thread);
    DWORD status;require(GetExitCodeThread(thread,&status)&&!status,"capture reply");CloseHandle(thread);
}
static LRESULT CALLBACK proc(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp) { return DefWindowProcW(hwnd,msg,wp,lp); }
static DWORD WINAPI worker(void *) {
    for(int i=0;i<iterations;++i){
        wchar_t name[64];swprintf(name,64,L"__wine_vulkan_stereo_v1_%08x",GetCurrentThreadId());
        require(SetPropW(child,name,reinterpret_cast<HANDLE>(0x55aa)),"previous property");
        VkWin32SurfaceCreateInfoKHR ci={};ci.sType=VK_STRUCTURE_TYPE_WIN32_SURFACE_CREATE_INFO_KHR;ci.hinstance=GetModuleHandleW(nullptr);ci.hwnd=child;
        VkSurfaceKHR surface=VK_NULL_HANDLE;VkResult result;bool acknowledged;
        {
            dxvk::wsi::WineStereoSurface request(child,true);
            result=create_surface(instance,&ci,nullptr,&surface);
            acknowledged=GetPropW(child,name)==reinterpret_cast<HANDLE>(0x18003);
            request.complete(result);
        }
        bool restored=GetPropW(child,name)==reinterpret_cast<HANDLE>(0x55aa);
        RemovePropW(child,name);
        std::printf("created iteration=%d result=%d acknowledged=%d restored=%d tid=%lu\n",i,result,acknowledged,restored,GetCurrentThreadId());std::fflush(stdout);
        require(result==VK_SUCCESS && acknowledged && restored,"surface handshake");
        if(!i){SetEvent(ready);require(WaitForSingleObject(release_surface,15000)==WAIT_OBJECT_0,"release wait");}
        auto before=ticks();destroy_surface(instance,surface,nullptr);auto after=ticks();
        std::printf("destroy iteration=%d start=%lld end=%lld\n",i,before,after);std::fflush(stdout);
    }
    SetEvent(done);return 0;
}
static HANDLE start_worker(int count) {
    iterations=count;ResetEvent(ready);ResetEvent(release_surface);ResetEvent(done);
    HANDLE thread=CreateThread(nullptr,0,worker,nullptr,0,nullptr);require(thread!=nullptr,"surface worker");wait_event(ready);return thread;
}
static void finish_worker(HANDLE thread) {
    SetEvent(release_surface);wait_event(done);wait_event(thread);DWORD status;require(GetExitCodeThread(thread,&status)&&!status,"worker result");CloseHandle(thread);
}
int main() {
    HMODULE library=LoadLibraryW(L"vulkan-1.dll");require(library!=nullptr,"Vulkan loader");
    auto get=reinterpret_cast<PFN_vkGetInstanceProcAddr>(GetProcAddress(library,"vkGetInstanceProcAddr"));require(get!=nullptr,"loader function");
    auto create=reinterpret_cast<PFN_vkCreateInstance>(get(nullptr,"vkCreateInstance"));require(create!=nullptr,"create instance function");
    const char *extensions[]={"VK_KHR_surface","VK_KHR_win32_surface"};VkInstanceCreateInfo ci={};ci.sType=VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;ci.enabledExtensionCount=2;ci.ppEnabledExtensionNames=extensions;
    require(create(&ci,nullptr,&instance)==VK_SUCCESS,"instance");
    create_surface=reinterpret_cast<PFN_vkCreateWin32SurfaceKHR>(get(instance,"vkCreateWin32SurfaceKHR"));destroy_surface=reinterpret_cast<PFN_vkDestroySurfaceKHR>(get(instance,"vkDestroySurfaceKHR"));require(create_surface&&destroy_surface,"surface entry points");
    auto destroy_instance=reinterpret_cast<PFN_vkDestroyInstance>(get(instance,"vkDestroyInstance"));
    WNDCLASSW cls={};cls.lpfnWndProc=proc;cls.hInstance=GetModuleHandleW(nullptr);cls.lpszClassName=L"SurfaceLifetime";cls.hbrBackground=static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));require(RegisterClassW(&cls)!=0,"class");
    owner_a=CreateWindowW(cls.lpszClassName,L"Lifetime Owner A",WS_POPUP|WS_VISIBLE,24,24,320,240,nullptr,nullptr,cls.hInstance,nullptr);
    owner_b=CreateWindowW(cls.lpszClassName,L"Lifetime Owner B",WS_POPUP|WS_VISIBLE,420,24,320,240,nullptr,nullptr,cls.hInstance,nullptr);
    child=CreateWindowW(cls.lpszClassName,L"Lifetime child",WS_CHILD|WS_VISIBLE,0,0,320,200,owner_a,nullptr,cls.hInstance,nullptr);require(owner_a&&owner_b&&child,"windows");
    ready=CreateEventW(nullptr,TRUE,FALSE,nullptr);release_surface=CreateEventW(nullptr,TRUE,FALSE,nullptr);done=CreateEventW(nullptr,TRUE,FALSE,nullptr);require(ready&&release_surface&&done,"events");
    wchar_t name[64];swprintf(name,64,L"__wine_vulkan_stereo_v1_%08x",GetCurrentThreadId());
    require(SetPropW(child,name,reinterpret_cast<HANDLE>(0x66bb)),"scope previous property");
    {
        dxvk::wsi::WineStereoSurface outer(child,true);
        { dxvk::wsi::WineStereoSurface inner(child,true); }
        require(GetPropW(child,name)==reinterpret_cast<HANDLE>(0x10003),"nested request restoration");
    }
    require(GetPropW(child,name)==reinterpret_cast<HANDLE>(0x66bb),"outer restoration");RemovePropW(child,name);
    std::puts("PASS helper nested property restoration");
    HANDLE thread=start_worker(1);capture(0);
    require(SetParent(child,owner_b)!=nullptr,"reparent");ShowWindow(child,SW_HIDE);ShowWindow(child,SW_SHOW);pump();capture(1);
    require(DestroyWindow(child),"destroy native window");pump();capture(2);
    SetLastError(0);
    {
        dxvk::wsi::WineStereoSurface invalid(child,true);
        DWORD error=GetLastError();
        std::printf("helper_invalid_window error=%lu vulkan_calls=0\n",error);std::fflush(stdout);
        require(error==ERROR_INVALID_WINDOW_HANDLE,"invalid window request failure");
    }
    finish_worker(thread);capture(3);
    child=CreateWindowW(cls.lpszClassName,L"Lifetime recreated",WS_CHILD|WS_VISIBLE,0,0,320,200,owner_a,nullptr,cls.hInstance,nullptr);require(child!=nullptr,"recreate window");
    thread=start_worker(16);capture(4);SetEvent(release_surface);
    unsigned moves=0;DWORD start=GetTickCount();
    while(WaitForSingleObject(done,0)!=WAIT_OBJECT_0){
        require(GetTickCount()-start<15000,"concurrency timeout");auto before=ticks();
        require(SetParent(child,(moves&1)?owner_a:owner_b)!=nullptr,"concurrent reparent");
        SetWindowPos(child,nullptr,moves%3,moves%5,320,200,SWP_NOZORDER);pump();auto after=ticks();
        std::printf("move iteration=%u start=%lld end=%lld\n",moves,before,after);std::fflush(stdout);++moves;
    }
    finish_worker(thread);require(moves>0,"concurrent operations");capture(5);
    require(DestroyWindow(child),"destroy recreated window");DestroyWindow(owner_a);DestroyWindow(owner_b);
    CloseHandle(ready);CloseHandle(release_surface);CloseHandle(done);destroy_instance(instance,nullptr);FreeLibrary(library);
    std::puts("PASS surface lifetime property restoration and concurrent owner operations");return failures?1:0;
}
