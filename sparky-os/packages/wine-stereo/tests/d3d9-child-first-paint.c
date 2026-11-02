#define COBJMACROS
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#include <string.h>

static IDirect3DDevice9 *device;
static IDirect3DSurface9 *source;
static HWND render_window;
static int capture_phase = -1, pair, present_count, paint_count;

static void check(HRESULT hr, int line)
{
    if (FAILED(hr)) { printf("FAIL line=%d hr=%08lx\n", line, (unsigned long)hr); fflush(stdout); ExitProcess(2); }
}
#define CHECK(call) check((call), __LINE__)

static void capture(int phase)
{
    char line[32];
    printf("phase=%d logical=320x200 frame=ready presents=%d paints=%d\n", phase, present_count, paint_count);
    fflush(stdout);
    if (!fgets(line, sizeof(line), stdin)) ExitProcess(91);
}

static void draw(int stamp)
{
    D3DLOCKED_RECT lock;
    IDirect3DSurface9 *back;
    CHECK(IDirect3DSurface9_LockRect(source, &lock, NULL, 0));
    for (int y = 0; y < 200; ++y)
        for (int x = 0; x < 320; ++x)
        {
            int eye = pair && x >= 160, xx = pair ? x % 160 : x;
            ((DWORD *)((char *)lock.pBits + y * lock.Pitch))[x] =
                0xff000000u | ((xx & 255) << 16) | ((199 - y) << 8) | (eye << 7) | ((xx >> 8) << 3) | stamp;
        }
    CHECK(IDirect3DSurface9_UnlockRect(source));
    CHECK(IDirect3DDevice9_GetBackBuffer(device, 0, 0, D3DBACKBUFFER_TYPE_MONO, &back));
    CHECK(IDirect3DDevice9_UpdateSurface(device, source, NULL, back, NULL));
    IDirect3DSurface9_Release(back);
    CHECK(IDirect3DDevice9_Present(device, NULL, NULL, NULL, NULL));
    ++present_count;
}

static LRESULT CALLBACK proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    if (message == WM_PAINT)
    {
        PAINTSTRUCT paint;
        int phase = window == render_window ? capture_phase : -1;
        BeginPaint(window, &paint);
        if (window == render_window) ++paint_count;
        if (phase >= 0 && device)
        {
            capture_phase = -1;
            draw(phase);
        }
        EndPaint(window, &paint);
        if (phase >= 0 && device) capture(phase);
        return 0;
    }
    return DefWindowProcA(window, message, wparam, lparam);
}

static void pump(void)
{
    MSG message;
    while (PeekMessageA(&message, NULL, 0, 0, PM_REMOVE))
    {
        TranslateMessage(&message);
        DispatchMessageA(&message);
    }
}

int main(int argc, char **argv)
{
    WNDCLASSA cls = {0};
    cls.style = CS_OWNDC; cls.lpfnWndProc = proc; cls.hInstance = GetModuleHandleA(NULL);
    cls.lpszClassName = "D3D9FirstPaint"; cls.hbrBackground = GetStockObject(BLACK_BRUSH);
    if (!RegisterClassA(&cls)) return 3;
    HWND a = CreateWindowA(cls.lpszClassName, "D3D9 Owner A", WS_POPUP | WS_VISIBLE, 24, 24, 320, 240, NULL, NULL, cls.hInstance, NULL);
    HWND b = CreateWindowA(cls.lpszClassName, "D3D9 Owner B", WS_POPUP | WS_VISIBLE, 420, 24, 320, 240, NULL, NULL, cls.hInstance, NULL);
    render_window = CreateWindowA(cls.lpszClassName, "D3D9 live child", WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS, 0, 0, 320, 200, a, NULL, cls.hInstance, NULL);
    HWND panel = CreateWindowA("STATIC", "ordinary clip panel", WS_CHILD | WS_VISIBLE | SS_BLACKRECT, 80, 40, 64, 48, a, NULL, cls.hInstance, NULL);
    if (!a || !b || !render_window || !panel) return 4;
    SetWindowPos(panel, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    IDirect3D9 *api = Direct3DCreate9(D3D_SDK_VERSION);
    if (!api) return 5;
    D3DPRESENT_PARAMETERS pp = {0};
    pp.Windowed = TRUE; pp.SwapEffect = D3DSWAPEFFECT_DISCARD; pp.hDeviceWindow = render_window;
    pp.BackBufferWidth = 320; pp.BackBufferHeight = 200; pp.BackBufferFormat = D3DFMT_X8R8G8B8;
    pp.PresentationInterval = D3DPRESENT_INTERVAL_IMMEDIATE;
    CHECK(IDirect3D9_CreateDevice(api, 0, D3DDEVTYPE_HAL, render_window, D3DCREATE_SOFTWARE_VERTEXPROCESSING, &pp, &device));
    CHECK(IDirect3DDevice9_CreateOffscreenPlainSurface(device, 320, 200, D3DFMT_X8R8G8B8, D3DPOOL_SYSTEMMEM, &source, NULL));
    pair = argc > 1 && !strcmp(argv[1], "stereo");
    for (int frame = 0; frame < 12; ++frame) { pump(); draw(0); Sleep(50); }
    capture(0);
    ShowWindow(render_window, SW_HIDE); pump(); capture(1);
    capture_phase = 2;
    ShowWindow(render_window, SW_SHOW);
    UpdateWindow(render_window); pump();
    if (capture_phase != -1) { puts("FAIL show generated no paint"); return 6; }
    if (!SetParent(render_window, b) || !SetParent(panel, b)) return 7;
    SetWindowPos(panel, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    pump(); /* Finish ordinary owner/panel paints before the first GPU repaint. */
    capture_phase = 3;
    RedrawWindow(render_window, NULL, NULL, RDW_INVALIDATE | RDW_UPDATENOW);
    if (capture_phase != -1) { puts("FAIL redraw generated no paint"); return 8; }
    DestroyWindow(render_window); render_window = NULL; pump(); capture(4);
    IDirect3DSurface9_Release(source); source = NULL;
    IDirect3DDevice9_Release(device); device = NULL; pump(); capture(5);
    IDirect3D9_Release(api);
    DestroyWindow(panel); DestroyWindow(a); DestroyWindow(b);
    puts("PASS first paint and detach");
    return 0;
}
