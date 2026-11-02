#define COBJMACROS
#include <windows.h>
#include <windowsx.h>
#include <d3d9.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
static IDirect3DDevice9 *devices[2];
static IDirect3DSurface9 *sources[2];
static HWND children[2];
static int received=-1, click_x, click_y, pair, presents[2], paint_mask, input_failures;
static void draw(int n);
static void check(HRESULT hr,int line) {if(FAILED(hr)){printf("FAIL line=%d hr=%08lx\n",line,(unsigned long)hr);fflush(stdout);ExitProcess(2);}}
#define CHECK(c) check((c),__LINE__)
static LRESULT CALLBACK proc(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp)
{
 if(msg==WM_LBUTTONDOWN){received=hwnd==children[0]?0:hwnd==children[1]?1:2;click_x=GET_X_LPARAM(lp);click_y=GET_Y_LPARAM(lp);return 0;}
 if(msg==WM_PAINT){PAINTSTRUCT p;BeginPaint(hwnd,&p);
  for(int i=0;i<2;++i)if(hwnd==children[i] && (paint_mask&(1<<i))){paint_mask &= ~(1<<i);draw(i);}
  EndPaint(hwnd,&p);return 0;}
 return DefWindowProcA(hwnd,msg,wp,lp);
}
static void pump(void){MSG m;while(PeekMessageA(&m,NULL,0,0,PM_REMOVE)){TranslateMessage(&m);DispatchMessageA(&m);}}
static void draw(int n)
{
 D3DLOCKED_RECT lock;IDirect3DSurface9 *back;
 CHECK(IDirect3DSurface9_LockRect(sources[n],&lock,NULL,0));
 for(int y=0;y<200;++y)for(int x=0;x<320;++x){int eye=pair&&x>=160,xx=pair?x%160:x;((DWORD*)((char*)lock.pBits+y*lock.Pitch))[x]=0xff000000u|((xx&255)<<16)|((199-y)<<8)|(eye<<7)|((xx>>8)<<3)|(n+1);}
 CHECK(IDirect3DSurface9_UnlockRect(sources[n]));
 CHECK(IDirect3DDevice9_GetBackBuffer(devices[n],0,0,D3DBACKBUFFER_TYPE_MONO,&back));
 CHECK(IDirect3DDevice9_UpdateSurface(devices[n],sources[n],NULL,back,NULL));IDirect3DSurface9_Release(back);
 CHECK(IDirect3DDevice9_Present(devices[n],NULL,NULL,NULL,NULL));++presents[n];
}
static DWORD WINAPI read_capture_reply(void *arg)
{
 char line[32];
 return fgets(line,sizeof(line),stdin) ? 0 : 91;
}
static void capture(int phase)
{
 DWORD status=0,start=GetTickCount();unsigned pumps=0;
 printf("phase=%d logical=320x200 frame=ready presents=%d,%d\n",phase,presents[0],presents[1]);fflush(stdout);
 if(getenv("WINE254_CAPTURE_PUMP"))
 {
  HANDLE reader=CreateThread(NULL,0,read_capture_reply,NULL,0,NULL);
  if(!reader)ExitProcess(92);
  for(;;)
  {
   DWORD wait=MsgWaitForMultipleObjectsEx(1,&reader,10,QS_ALLINPUT,MWMO_INPUTAVAILABLE);
   if(wait==WAIT_OBJECT_0)break;
   if(wait==WAIT_FAILED || GetTickCount()-start>30000)ExitProcess(94);
   pump();++pumps;
  }
  if(!GetExitCodeThread(reader,&status))ExitProcess(95);
  CloseHandle(reader);
 }
 else status=read_capture_reply(NULL);
 if(status)ExitProcess(status);
 printf("capture_done phase=%d pumps=%u presents=%d,%d\n",phase,pumps,presents[0],presents[1]);fflush(stdout);
}
static void click(HWND owner,int target)
{
 POINT p={250,150};INPUT events[2]={{0},{0}};ClientToScreen(owner,&p);received=-1;
 RECT virtual_rect, physical_rect;POINT cursor;
 GetWindowRect(owner,&virtual_rect);
 DPI_AWARENESS_CONTEXT previous=SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
 GetWindowRect(owner,&physical_rect);UINT system_dpi=GetDpiForSystem();SetThreadDpiAwarenessContext(previous);
 if(!SetCursorPos(p.x,p.y))ExitProcess(10);
 GetCursorPos(&cursor);
 printf("geometry requested=%ld,%ld cursor=%ld,%ld virtual=%ld,%ld,%ld,%ld physical=%ld,%ld,%ld,%ld system_dpi=%u\n",p.x,p.y,cursor.x,cursor.y,virtual_rect.left,virtual_rect.top,virtual_rect.right,virtual_rect.bottom,physical_rect.left,physical_rect.top,physical_rect.right,physical_rect.bottom,system_dpi);fflush(stdout);
 events[0].type=events[1].type=INPUT_MOUSE;events[0].mi.dwFlags=MOUSEEVENTF_LEFTDOWN;events[1].mi.dwFlags=MOUSEEVENTF_LEFTUP;
 if(SendInput(2,events,sizeof(INPUT))!=2)ExitProcess(11);
 for(int i=0;i<50&&received==-1;++i){pump();Sleep(10);}
 printf("input target=%d received=%d x=%d y=%d dpi=%u\n",target,received,click_x,click_y,GetDpiForWindow(owner));fflush(stdout);
 if(received!=target||click_x!=(target?170:250)||click_y!=(target?110:150))++input_failures;
}
int main(int argc,char **argv)
{
 if(getenv("WINE254_AWARE") && !SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2))return 14;
 WNDCLASSA cls={0};cls.style=CS_OWNDC;cls.lpfnWndProc=proc;cls.hInstance=GetModuleHandleA(NULL);cls.lpszClassName="D3D9Multiple";cls.hbrBackground=GetStockObject(BLACK_BRUSH);if(!RegisterClassA(&cls))return 3;
 HWND owner=CreateWindowA(cls.lpszClassName,"D3D9 Multiple Owner",WS_POPUP|WS_VISIBLE,24,24,320,240,NULL,NULL,cls.hInstance,NULL);
 for(int i=0;i<2;++i)children[i]=CreateWindowA(cls.lpszClassName,i?"child1":"child0",WS_CHILD|WS_VISIBLE|WS_CLIPSIBLINGS,80*i,40*i,320,200,owner,NULL,cls.hInstance,NULL);
 HWND panel=CreateWindowA("STATIC","ordinary clip panel",WS_CHILD|WS_VISIBLE|SS_BLACKRECT,80,40,64,48,owner,NULL,cls.hInstance,NULL);
 IDirect3D9 *api=Direct3DCreate9(D3D_SDK_VERSION);if(!api)return 5;
 pair=argc>1&&!strcmp(argv[1],"stereo");
 for(int i=0;i<2;++i){D3DPRESENT_PARAMETERS pp={0};pp.Windowed=TRUE;pp.SwapEffect=D3DSWAPEFFECT_DISCARD;pp.hDeviceWindow=children[i];pp.BackBufferWidth=320;pp.BackBufferHeight=200;pp.BackBufferFormat=D3DFMT_X8R8G8B8;pp.PresentationInterval=D3DPRESENT_INTERVAL_IMMEDIATE;
 CHECK(IDirect3D9_CreateDevice(api,0,D3DDEVTYPE_HAL,children[i],D3DCREATE_SOFTWARE_VERTEXPROCESSING,&pp,&devices[i]));CHECK(IDirect3DDevice9_CreateOffscreenPlainSurface(devices[i],320,200,D3DFMT_X8R8G8B8,D3DPOOL_SYSTEMMEM,&sources[i],NULL));}
 SetWindowPos(children[1],HWND_TOP,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE);SetWindowPos(panel,HWND_TOP,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE);
 for(int i=0;i<12;++i){pump();draw(0);draw(1);Sleep(50);}click(owner,1);capture(0);
 SetWindowPos(children[0],HWND_TOP,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE);SetWindowPos(panel,HWND_TOP,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE);pump();draw(0);draw(1);click(owner,0);capture(1);
 ShowWindow(owner,SW_HIDE);pump();capture(2);
 ShowWindow(owner,SW_SHOW);pump();paint_mask=3;
 RedrawWindow(children[0],NULL,NULL,RDW_INVALIDATE|RDW_UPDATENOW);
 RedrawWindow(children[1],NULL,NULL,RDW_INVALIDATE|RDW_UPDATENOW);
 if(paint_mask)return 13;
 /* Drain the ordinary UI expose/paint events after the WM maps the owner.
  * paint_mask is already zero, so this cannot submit another GPU frame. */
 for(int i=0;i<10;++i){MsgWaitForMultipleObjectsEx(0,NULL,10,QS_ALLINPUT,MWMO_INPUTAVAILABLE);pump();}
 click(owner,0);capture(3);
 SetWindowPos(owner,HWND_TOP,420,24,320,240,0);pump();draw(0);draw(1);click(owner,0);capture(4);
 DestroyWindow(children[0]);children[0]=NULL;pump();draw(1);click(owner,1);capture(5);
 IDirect3DSurface9_Release(sources[0]);IDirect3DDevice9_Release(devices[0]);pump();capture(6);
 DestroyWindow(owner);pump();capture(7);
 IDirect3DSurface9_Release(sources[1]);IDirect3DDevice9_Release(devices[1]);IDirect3D9_Release(api);pump();capture(8);
 printf("input_failures=%d\n",input_failures);if(input_failures)return 12;
 puts("PASS multiple overlap input lifecycle");return 0;
}
