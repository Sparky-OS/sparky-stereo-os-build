/* SPDX-License-Identifier: MIT */
/* Address-coded WGL child inside an ordinary Win32 owner. */
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { CMD_OPEN = WM_APP + 1, CMD_RESIZE, CMD_MENU, CMD_CLOSE_MENU, CMD_HIDE, CMD_SHOW, CMD_DESTROY, CMD_EXIT, CMD_PROBE, CMD_REDRAW, CMD_PAINT };
static HWND owner, child;
static HDC dc;
static HGLRC context;
static int stereo, width = 240, height = 140;
static const char *trace_directory;
static unsigned frames, timers, owner_paints, child_paints, probes;
static int paint_redraw, stepping, rebind;

static void readback( const char *stage, GLenum buffer, int eye, int save )
{
    unsigned char *pixels;
    unsigned errors = 0;
    GLint viewport[4];
    char path[MAX_PATH];
    FILE *file;
    int x, y;
    pixels = malloc( width * height * 3 );
    if (!pixels) ExitProcess( 30 );
    glPixelStorei( GL_PACK_ALIGNMENT, 1 );
    glReadBuffer( buffer );
    glReadPixels( 0, 0, width, height, GL_RGB, GL_UNSIGNED_BYTE, pixels );
    glGetIntegerv( GL_VIEWPORT, viewport );
    for (y = 0; y < height; ++y) for (x = 0; x < width; ++x)
    {
        unsigned char *v = pixels + 3 * (y * width + x);
        if (v[0] != x || v[1] != y || v[2] != (eye << 7)) ++errors;
    }
    printf( "READ stage=%s frame=%u probe=%u eye=%d size=%dx%d viewport=%d,%d,%d,%d errors=%u first=%u,%u,%u last=%u,%u,%u gl_error=%u\n",
            stage, frames, probes, eye, width, height, viewport[0], viewport[1], viewport[2], viewport[3], errors,
            pixels[0], pixels[1], pixels[2], pixels[3*(width*height-1)], pixels[3*(width*height-1)+1], pixels[3*(width*height-1)+2], glGetError() );
    if (save)
    {
        snprintf( path, sizeof(path), "%s/probe-%u-%s-%d.rgb", trace_directory, probes, stage, eye );
        if (!(file = fopen( path, "wb" ))) ExitProcess( 31 );
        if (fwrite( pixels, 3, width * height, file ) != (unsigned)(width * height)) ExitProcess( 32 );
        fclose( file );
    }
    free( pixels );
}

static void probe(void)
{
    BITMAPINFO info = {0};
    HDC screen_dc, memory;
    HBITMAP bitmap, previous;
    unsigned char *pixels;
    char path[MAX_PATH]; FILE *file;
    int x, y, eye; unsigned errors = 0;
    if (!trace_directory || !context) return;
    ++probes;
    for (eye = 0; eye < (stereo ? 2 : 1); ++eye)
    {
        readback( "back", stereo ? (eye ? GL_BACK_RIGHT : GL_BACK_LEFT) : GL_BACK, eye, 1 );
        readback( "front", stereo ? (eye ? GL_FRONT_RIGHT : GL_FRONT_LEFT) : GL_FRONT, eye, 1 );
    }
    info.bmiHeader.biSize = sizeof(info.bmiHeader);
    info.bmiHeader.biWidth = width; info.bmiHeader.biHeight = -height;
    info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32; info.bmiHeader.biCompression = BI_RGB;
    screen_dc = GetDC( owner ); memory = CreateCompatibleDC( screen_dc );
    bitmap = CreateDIBSection( screen_dc, &info, DIB_RGB_COLORS, (void **)&pixels, NULL, 0 );
    if (!bitmap || !memory) ExitProcess( 33 );
    previous = SelectObject( memory, bitmap );
    if (!BitBlt( memory, 0, 0, width, height, screen_dc, 20, 70, SRCCOPY )) ExitProcess( 34 );
    GdiFlush();
    snprintf( path, sizeof(path), "%s/probe-%u-gdi.bgra", trace_directory, probes );
    if (!(file = fopen( path, "wb" ))) ExitProcess( 35 );
    if (fwrite( pixels, 4, width * height, file ) != (unsigned)(width * height)) ExitProcess( 36 );
    fclose( file );
    for (y = 0; y < height; ++y) for (x = 0; x < width; ++x)
    {
        unsigned char *v = pixels + 4 * (y * width + x);
        if (v[2] != x || v[1] != height-y-1 || v[0] != 0) ++errors;
    }
    printf( "PROBE id=%u frames=%u timers=%u owner_paints=%u child_paints=%u size=%dx%d visible=%d gdi_errors=%u first=%u,%u,%u\n",
            probes, frames, timers, owner_paints, child_paints, width, height, IsWindowVisible(child), errors, pixels[2], pixels[1], pixels[0] );
    SelectObject( memory, previous ); DeleteObject( bitmap ); DeleteDC( memory ); ReleaseDC( owner, screen_dc );
    fflush( stdout );
}

static void draw(void)
{
    unsigned char *pixels;
    RECT rect;
    int x, y, eye;
    if (!context || !IsWindowVisible( child )) return;
    GetClientRect( child, &rect );
    if (rect.right != width || rect.bottom != height) ExitProcess( 20 );
    if (rebind && !wglMakeCurrent( dc, context )) ExitProcess( 37 );
    pixels = malloc( width * height * 3 );
    if (!pixels) ExitProcess( 21 );
    glViewport( 0, 0, width, height );
    glMatrixMode( GL_PROJECTION ); glLoadIdentity();
    glOrtho( 0, width, 0, height, -1, 1 );
    glMatrixMode( GL_MODELVIEW ); glLoadIdentity();
    glDisable( GL_DITHER );
    glPixelStorei( GL_UNPACK_ALIGNMENT, 1 );
    for (eye = 0; eye < (stereo ? 2 : 1); ++eye)
    {
        for (y = 0; y < height; ++y) for (x = 0; x < width; ++x)
        {
            int offset = 3 * (y * width + x);
            pixels[offset] = x;
            pixels[offset + 1] = y;
            pixels[offset + 2] = eye << 7;
        }
        glDrawBuffer( stereo ? (eye ? GL_BACK_RIGHT : GL_BACK_LEFT) : GL_BACK );
        glRasterPos2i( 0, 0 );
        glDrawPixels( width, height, GL_RGB, GL_UNSIGNED_BYTE, pixels );
    }
    free( pixels );
    ++frames;
    if (trace_directory) for (eye = 0; eye < (stereo ? 2 : 1); ++eye)
        readback( "before-swap", stereo ? (eye ? GL_BACK_RIGHT : GL_BACK_LEFT) : GL_BACK, eye, 0 );
    if (trace_directory) { printf( "SWAP begin frame=%u tick=%lu\n", frames, GetTickCount() ); fflush( stdout ); }
    if (glGetError() != GL_NO_ERROR || !SwapBuffers( dc )) ExitProcess( 22 );
    if (trace_directory)
    {
        for (eye = 0; eye < (stereo ? 2 : 1); ++eye)
            readback( "after-swap", stereo ? (eye ? GL_FRONT_RIGHT : GL_FRONT_LEFT) : GL_FRONT, eye, 0 );
        printf( "FRAME id=%u timer=%u paints=%u,%u tick=%lu\n", frames, timers, owner_paints, child_paints, GetTickCount() );
        fflush( stdout );
    }
}

static void close_view(void)
{
    if (!child) return;
    wglMakeCurrent( NULL, NULL );
    wglDeleteContext( context ); context = NULL;
    ReleaseDC( child, dc ); dc = NULL;
    DestroyWindow( child ); child = NULL;
    InvalidateRect( owner, NULL, TRUE );
}

static void open_view(void)
{
    PIXELFORMATDESCRIPTOR req = {0}, actual = {0};
    GLboolean actual_stereo;
    int format;
    if (child) return;
    child = CreateWindowA( "WineChildView", "WGL child viewport", WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
                           20, 70, width, height, owner, NULL, GetModuleHandleA( NULL ), NULL );
    if (!child) ExitProcess( 2 );
    dc = GetDC( child );
    req.nSize = sizeof(req); req.nVersion = 1;
    req.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    if (stereo) req.dwFlags |= PFD_STEREO;
    req.iPixelType = PFD_TYPE_RGBA; req.cColorBits = 24;
    format = ChoosePixelFormat( dc, &req );
    if (!format || !SetPixelFormat( dc, format, &req )) ExitProcess( 3 );
    if (!DescribePixelFormat( dc, format, sizeof(actual), &actual )) ExitProcess( 4 );
    context = wglCreateContext( dc );
    if (!context || !wglMakeCurrent( dc, context )) ExitProcess( 5 );
    glGetBooleanv( GL_STEREO, &actual_stereo );
    printf( "VIEW requested=%d actual=%d format_stereo=%d renderer=%s\n", stereo, actual_stereo,
            !!(actual.dwFlags & PFD_STEREO), glGetString( GL_RENDERER ) );
    fflush( stdout );
    if (!!actual_stereo != stereo || !!(actual.dwFlags & PFD_STEREO) != stereo) ExitProcess( 77 );
    draw();
}

static DWORD WINAPI commands( void *unused )
{
    static const char *names[] = {"open", "resize", "menu", "close-menu", "hide", "show", "destroy", "exit", "probe", "redraw", "paint"};
    char command[32];
    unsigned i;
    (void)unused;
    while (scanf( "%31s", command ) == 1)
        for (i = 0; i < sizeof(names) / sizeof(names[0]); ++i)
            if (!strcmp( command, names[i] )) PostMessageA( owner, CMD_OPEN + i, 0, 0 );
    return 0;
}

static LRESULT CALLBACK window_proc( HWND window, UINT message, WPARAM wp, LPARAM lp )
{
    if (trace_directory && message >= CMD_OPEN && message <= CMD_PAINT)
    { printf( "COMMAND begin id=%u frame=%u tick=%lu\n", message-CMD_OPEN, frames, GetTickCount() ); fflush( stdout ); }
    switch (message)
    {
    case CMD_OPEN: open_view(); break;
    case CMD_RESIZE:
        width = 200; height = 120;
        if (child) SetWindowPos( child, NULL, 0, 0, width, height, SWP_NOMOVE | SWP_NOZORDER );
        break;
    case CMD_MENU: SendMessageA( owner, WM_SYSCOMMAND, SC_KEYMENU, 'f' ); break;
    case CMD_CLOSE_MENU: EndMenu(); break;
    case CMD_HIDE: if (child) ShowWindow( child, SW_HIDE ); break;
    case CMD_SHOW: if (child) ShowWindow( child, SW_SHOW ); break;
    case CMD_DESTROY: close_view(); break;
    case CMD_EXIT: close_view(); DestroyWindow( owner ); break;
    case CMD_PROBE: probe(); break;
    case CMD_REDRAW: draw(); break;
    case CMD_PAINT: if (child) RedrawWindow( child, NULL, NULL, RDW_INVALIDATE | RDW_UPDATENOW ); break;
    case WM_TIMER: ++timers; draw(); InvalidateRect( owner, NULL, FALSE ); break;
    case WM_SIZE:
        if (trace_directory) { printf( "SIZE child=%d width=%u height=%u tick=%lu\n", !!(GetWindowLongA( window, GWL_STYLE ) & WS_CHILD), LOWORD(lp), HIWORD(lp), GetTickCount() ); fflush( stdout ); }
        return DefWindowProcA( window, message, wp, lp );
    case WM_PAINT:
    {
        PAINTSTRUCT paint; RECT rect;
        HDC paint_dc = BeginPaint( window, &paint );
        if (window == owner)
        {
            HBRUSH brush = CreateSolidBrush( RGB(32,64,96) );
            GetClientRect( window, &rect ); FillRect( paint_dc, &rect, brush ); DeleteObject( brush );
            SetBkMode( paint_dc, TRANSPARENT ); SetTextColor( paint_dc, RGB(255,255,255) );
            TextOutA( paint_dc, 20, 16, "Ordinary owner UI", 17 );
        }
        if (window == owner) ++owner_paints; else ++child_paints;
        EndPaint( window, &paint );
        if (paint_redraw && window == child) draw();
        break;
    }
    case WM_DESTROY: if (window == owner) PostQuitMessage( 0 ); break;
    default: return DefWindowProcA( window, message, wp, lp );
    }
    if (trace_directory && message >= CMD_OPEN && message <= CMD_PAINT)
    { printf( "COMMAND end id=%u frame=%u tick=%lu\n", message-CMD_OPEN, frames, GetTickCount() ); fflush( stdout ); }
    return 0;
}

int main( int argc, char **argv )
{
    WNDCLASSA cls = {0}; HMENU bar, menu; MSG message; HANDLE reader;
    trace_directory = argc > 2 ? argv[2] : NULL;
    paint_redraw = argc > 3 && strstr( argv[3], "paint-redraw" );
    stepping = argc > 3 && strstr( argv[3], "step" );
    rebind = argc > 3 && strstr( argv[3], "rebind" );
    stereo = argc > 1 && !strcmp( argv[1], "stereo" );
    cls.lpfnWndProc = window_proc; cls.hInstance = GetModuleHandleA( NULL );
    cls.lpszClassName = "WineChildOwner";
    if (!RegisterClassA( &cls )) return 6;
    cls.style = CS_OWNDC; cls.lpszClassName = "WineChildView";
    if (!RegisterClassA( &cls )) return 7;
    bar = CreateMenu(); menu = CreatePopupMenu();
    AppendMenuA( menu, MF_STRING, 101, "Ordinary menu" );
    AppendMenuA( bar, MF_POPUP, (UINT_PTR)menu, "&File" );
    owner = CreateWindowA( "WineChildOwner", "Wine mixed owner fixture", WS_OVERLAPPEDWINDOW | WS_VISIBLE | WS_CLIPCHILDREN,
                           40, 40, 480, 360, NULL, bar, cls.hInstance, NULL );
    if (!owner) return 8;
    if (!stepping) SetTimer( owner, 1, 50, NULL );
    reader = CreateThread( NULL, 0, commands, NULL, 0, NULL );
    if (!reader) return 9;
    CloseHandle( reader );
    printf( "READY bits=%u stereo=%d\n", (unsigned)(8 * sizeof(void *)), stereo ); fflush( stdout );
    while (GetMessageA( &message, NULL, 0, 0 ) > 0) { TranslateMessage( &message ); DispatchMessageA( &message ); }
    puts( "PASS exit" ); return 0;
}
