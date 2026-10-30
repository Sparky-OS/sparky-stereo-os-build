/* SPDX-License-Identifier: MIT */
#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static LRESULT CALLBACK proc(HWND w, UINT m, WPARAM a, LPARAM b) { return DefWindowProcA(w,m,a,b); }
#define CHECK(call) do { HRESULT hr=(call); if(FAILED(hr)) { printf("FAIL line=%d hr=%08lx\n",__LINE__,(unsigned long)hr); return 2; } } while(0)
int main(int argc,char **argv) {
    WNDCLASSA cls={0};cls.style=CS_OWNDC;cls.lpfnWndProc=proc;cls.hInstance=GetModuleHandleA(NULL);cls.lpszClassName="D3D11Pair";
    if(!RegisterClassA(&cls))return 3;
    HWND w=CreateWindowA(cls.lpszClassName,"Wine D3D11 pair fixture",WS_POPUP|WS_VISIBLE,24,24,320,200,NULL,NULL,cls.hInstance,NULL);
    if(!w)return 4;
    DXGI_SWAP_CHAIN_DESC desc={0};desc.BufferDesc.Width=320;desc.BufferDesc.Height=200;desc.BufferDesc.Format=DXGI_FORMAT_B8G8R8A8_UNORM;desc.SampleDesc.Count=1;desc.BufferUsage=DXGI_USAGE_RENDER_TARGET_OUTPUT;desc.BufferCount=1;desc.OutputWindow=w;desc.Windowed=TRUE;desc.SwapEffect=DXGI_SWAP_EFFECT_DISCARD;
    ID3D11Device *dev=NULL;ID3D11DeviceContext *ctx=NULL;IDXGISwapChain *swap=NULL;
    D3D_FEATURE_LEVEL requested=D3D_FEATURE_LEVEL_11_0,actual;
    CHECK(D3D11CreateDeviceAndSwapChain(NULL,D3D_DRIVER_TYPE_HARDWARE,NULL,0,&requested,1,D3D11_SDK_VERSION,&desc,&swap,&dev,&actual,&ctx));
    printf("pointer_bits=%u d3d11=ready feature_level=%x\n",(unsigned)(8*sizeof(void*)),actual);fflush(stdout);
    int pair=argc>1&&!strcmp(argv[1],"stereo");
    for(int phase=0;phase<2;phase++) {
        unsigned width=phase?256:320,height=phase?160:200;
        if(phase){SetWindowPos(w,NULL,0,0,width,height,SWP_NOMOVE|SWP_NOZORDER);ID3D11DeviceContext_ClearState(ctx);CHECK(IDXGISwapChain_ResizeBuffers(swap,1,width,height,DXGI_FORMAT_B8G8R8A8_UNORM,0));}
        ID3D11Texture2D *back=NULL;CHECK(IDXGISwapChain_GetBuffer(swap,0,&IID_ID3D11Texture2D,(void**)&back));
        DWORD *pixels=malloc(width*height*sizeof(*pixels));if(!pixels)return 5;
        for(unsigned y=0;y<height;y++)for(unsigned x=0;x<width;x++){unsigned eye=pair&&x>=width/2,xx=pair?x%(width/2):x;pixels[y*width+x]=0xff000000u|((xx&255)<<16)|((height-1-y)<<8)|(eye<<7)|((xx>>8)<<3);}
        for(int frame=0;frame<80;frame++){
            MSG msg;while(PeekMessageA(&msg,NULL,0,0,PM_REMOVE)){TranslateMessage(&msg);DispatchMessageA(&msg);}
            ID3D11DeviceContext_UpdateSubresource(ctx,(ID3D11Resource*)back,0,NULL,pixels,width*sizeof(*pixels),0);
            CHECK(IDXGISwapChain_Present(swap,0,0));
            if(frame==10){printf("phase=%d logical=%ux%u frame=ready\n",phase,width,height);fflush(stdout);}Sleep(50);
        }
        free(pixels);ID3D11Texture2D_Release(back);
    }
    ID3D11DeviceContext_ClearState(ctx);IDXGISwapChain_Release(swap);ID3D11DeviceContext_Release(ctx);ID3D11Device_Release(dev);DestroyWindow(w);puts("PASS resize and exit");return 0;
}
