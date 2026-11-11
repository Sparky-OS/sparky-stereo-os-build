/* Synthetic D3D9 paused-move control. The driver, never this fixture, declares stereo.
 * Each phase waits for one line on stdin after the observer has captured it.
 * No Present is issued between the initial image and the move/detach phases. */
#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#include <string.h>
static void pause_phase(int n) { char line[32]; MSG msg; while(PeekMessageA(&msg,NULL,0,0,PM_REMOVE)){TranslateMessage(&msg);DispatchMessageA(&msg);} printf("phase=%d logical=320x200 frame=ready\n",n); fflush(stdout); if(!fgets(line,sizeof(line),stdin)) ExitProcess(91); }
static LRESULT CALLBACK proc(HWND w,UINT m,WPARAM a,LPARAM b) { return DefWindowProcA(w,m,a,b); }
#define CHECK(call) do { HRESULT hr=(call); if(FAILED(hr)) { printf("FAIL line=%d hr=%08lx\n",__LINE__,(unsigned long)hr); return 2; } } while(0)
int main(int argc,char **argv) {
    WNDCLASSA cls={0}; cls.style=CS_OWNDC;cls.lpfnWndProc=proc;cls.hInstance=GetModuleHandleA(NULL);cls.lpszClassName="D3D9Pair";
    cls.hbrBackground=(HBRUSH)GetStockObject(BLACK_BRUSH);
    RegisterClassA(&cls);
    HWND a=CreateWindowA(cls.lpszClassName,"D3D9 Owner A",WS_POPUP|WS_VISIBLE,24,24,320,240,NULL,NULL,cls.hInstance,NULL);
    HWND b=CreateWindowA(cls.lpszClassName,"D3D9 Owner B",WS_POPUP|WS_VISIBLE,420,24,320,240,NULL,NULL,cls.hInstance,NULL);
    HWND w=CreateWindowA(cls.lpszClassName,"D3D9 live child",WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS,0,0,320,200,a,NULL,cls.hInstance,NULL);
    char setting[8];
    int clipped=GetEnvironmentVariableA("WINE254_CLIP",setting,sizeof(setting)) && setting[0]=='1';
    HWND panel=clipped?CreateWindowA("STATIC","ordinary black clip panel",WS_CHILD|WS_VISIBLE|SS_BLACKRECT,80,40,64,48,a,NULL,cls.hInstance,NULL):NULL;
    if(!a||!b||!w||(clipped&&!panel))return 4;
    if(panel)SetWindowPos(panel,HWND_TOP,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW);
    printf("clip_enabled=%d\n",clipped);
    IDirect3D9 *api=Direct3DCreate9(D3D_SDK_VERSION);if(!api)return 3;
    IDirect3DDevice9 *dev=NULL;
    D3DPRESENT_PARAMETERS pp={0};pp.Windowed=TRUE;pp.SwapEffect=D3DSWAPEFFECT_DISCARD;pp.hDeviceWindow=w;pp.BackBufferWidth=320;pp.BackBufferHeight=200;pp.BackBufferFormat=D3DFMT_X8R8G8B8;pp.PresentationInterval=D3DPRESENT_INTERVAL_IMMEDIATE;
    CHECK(IDirect3D9_CreateDevice(api,0,D3DDEVTYPE_HAL,w,D3DCREATE_SOFTWARE_VERTEXPROCESSING,&pp,&dev));
    printf("pointer_bits=%u d3d9=ready\n",(unsigned)(8*sizeof(void*)));fflush(stdout);
    int pair=argc>1&&!strcmp(argv[1],"stereo");
    for(int phase=0;phase<1;++phase) {
        int width=phase?256:320,height=phase?160:200;
        if(phase) {if(!SetParent(w,b))return 5;if(panel&&!SetParent(panel,b))return 6;if(panel)SetWindowPos(panel,HWND_TOP,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW);printf("reparented hwnd=%p parent=%p\n",w,GetParent(w));SetWindowPos(w,NULL,0,0,width,height,SWP_NOMOVE|SWP_NOZORDER);pp.BackBufferWidth=width;pp.BackBufferHeight=height;CHECK(IDirect3DDevice9_Reset(dev,&pp));}
        IDirect3DSurface9 *src=NULL,*dst=NULL;D3DLOCKED_RECT lock;
        CHECK(IDirect3DDevice9_CreateOffscreenPlainSurface(dev,width,height,D3DFMT_X8R8G8B8,D3DPOOL_SYSTEMMEM,&src,NULL));
        CHECK(IDirect3DSurface9_LockRect(src,&lock,NULL,0));
        for(int y=0;y<height;y++)for(int x=0;x<width;x++){int eye=pair&&x>=width/2,xx=pair?x%(width/2):x;((DWORD*)((char*)lock.pBits+y*lock.Pitch))[x]=0xff000000u|((xx&255)<<16)|((height-1-y)<<8)|(eye<<7)|((xx>>8)<<3);}
        CHECK(IDirect3DSurface9_UnlockRect(src));
        for(int frame=0;frame<12;frame++) {
            MSG msg;while(PeekMessageA(&msg,NULL,0,0,PM_REMOVE)){TranslateMessage(&msg);DispatchMessageA(&msg);}
            CHECK(IDirect3DDevice9_GetBackBuffer(dev,0,0,D3DBACKBUFFER_TYPE_MONO,&dst));
            CHECK(IDirect3DDevice9_UpdateSurface(dev,src,NULL,dst,NULL));IDirect3DSurface9_Release(dst);
            CHECK(IDirect3DDevice9_Present(dev,NULL,NULL,NULL,NULL));
            Sleep(50);
        }
        IDirect3DSurface9_Release(src);
    }
    pause_phase(0);
    SetWindowPos(w,NULL,16,16,320,200,SWP_NOZORDER); pause_phase(1);
    DestroyWindow(w);w=NULL; pause_phase(2);
    IDirect3DDevice9_Release(dev);dev=NULL; pause_phase(3);
    IDirect3D9_Release(api);if(panel)DestroyWindow(panel);DestroyWindow(w);DestroyWindow(a);DestroyWindow(b);puts("PASS resize and exit");return 0;
}
