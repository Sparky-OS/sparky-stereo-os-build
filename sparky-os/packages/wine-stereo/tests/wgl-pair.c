/* SPDX-License-Identifier: MIT */
/* Deterministic Win32 WGL counterpart to gl-stereo/tests/quad.c. */
#include <windows.h>
#include <GL/gl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static LRESULT CALLBACK window_proc( HWND window, UINT message, WPARAM wparam, LPARAM lparam )
{
    if (message == WM_CLOSE) { DestroyWindow( window ); return 0; }
    if (message == WM_DESTROY) { PostQuitMessage( 0 ); return 0; }
    return DefWindowProcA( window, message, wparam, lparam );
}

int main( int argc, char **argv )
{
    WNDCLASSA cls = {0};
    PIXELFORMATDESCRIPTOR requested = {0}, actual = {0};
    HWND window;
    HDC dc;
    HGLRC context;
    MSG message;
    GLboolean stereo;
    RECT rect;
    int format, phase, frame, eye, x, y, width, height, want_stereo;
    unsigned char *pixels, check[3];
    want_stereo = argc > 1 && !strcmp( argv[1], "stereo" );
    cls.style = CS_OWNDC;
    cls.lpfnWndProc = window_proc;
    cls.hInstance = GetModuleHandleA( NULL );
    cls.lpszClassName = "WineWglPair";
    if (!RegisterClassA( &cls )) return 2;
    window = CreateWindowA( cls.lpszClassName, "Wine WGL pair fixture", WS_POPUP | WS_VISIBLE,
                            24, 24, 320, 200, NULL, NULL, cls.hInstance, NULL );
    if (!window) return 3;
    dc = GetDC( window );
    requested.nSize = sizeof(requested);
    requested.nVersion = 1;
    requested.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
    if (want_stereo) requested.dwFlags |= PFD_STEREO;
    requested.iPixelType = PFD_TYPE_RGBA;
    requested.cColorBits = 24;
    format = ChoosePixelFormat( dc, &requested );
    if (!format || !SetPixelFormat( dc, format, &requested )) return 4;
    if (!DescribePixelFormat( dc, format, sizeof(actual), &actual )) return 5;
    context = wglCreateContext( dc );
    if (!context || !wglMakeCurrent( dc, context )) return 6;
    glGetBooleanv( GL_STEREO, &stereo );
    printf( "pointer_bits=%u requested_stereo=%d actual_stereo=%d format_stereo=%d renderer=%s\n",
            (unsigned)(8 * sizeof(void *)), want_stereo, stereo,
            !!(actual.dwFlags & PFD_STEREO), glGetString( GL_RENDERER ) );
    fflush( stdout );
    if (!!stereo != want_stereo || !!(actual.dwFlags & PFD_STEREO) != want_stereo) return 77;
    for (phase = 0; phase < 2; ++phase)
    {
        width = phase ? 256 : 320;
        height = phase ? 160 : 200;
        SetWindowPos( window, NULL, 0, 0, width, height, SWP_NOMOVE | SWP_NOZORDER );
        for (frame = 0; frame < 80; ++frame)
        {
            while (PeekMessageA( &message, NULL, 0, 0, PM_REMOVE ))
            {
                if (message.message == WM_QUIT) return 8;
                TranslateMessage( &message );
                DispatchMessageA( &message );
            }
            GetClientRect( window, &rect );
            if (rect.right != width || rect.bottom != height) return 9;
            glViewport( 0, 0, width, height );
            glMatrixMode( GL_PROJECTION ); glLoadIdentity();
            glOrtho( 0, width, 0, height, -1, 1 );
            glMatrixMode( GL_MODELVIEW ); glLoadIdentity();
            glDisable( GL_DITHER );
            glPixelStorei( GL_UNPACK_ALIGNMENT, 1 );
            glPixelStorei( GL_PACK_ALIGNMENT, 1 );
            pixels = malloc( width * height * 3 );
            if (!pixels) return 10;
            for (eye = 0; eye < (stereo ? 2 : 1); ++eye)
            {
                for (y = 0; y < height; ++y) for (x = 0; x < width; ++x)
                {
                    int offset = 3 * (y * width + x);
                    pixels[offset] = x & 255;
                    pixels[offset + 1] = y & 255;
                    pixels[offset + 2] = (eye << 7) | ((x >> 8) << 3);
                }
                glDrawBuffer( stereo ? (eye ? GL_BACK_RIGHT : GL_BACK_LEFT) : GL_BACK );
                glRasterPos2i( 0, 0 );
                glDrawPixels( width, height, GL_RGB, GL_UNSIGNED_BYTE, pixels );
                glReadBuffer( stereo ? (eye ? GL_BACK_RIGHT : GL_BACK_LEFT) : GL_BACK );
                glReadPixels( 13, 17, 1, 1, GL_RGB, GL_UNSIGNED_BYTE, check );
                if (check[0] != 13 || check[1] != 17 || check[2] != (eye << 7)) return 11;
            }
            free( pixels );
            if (glGetError() != GL_NO_ERROR || !SwapBuffers( dc )) return 12;
            if (frame == 10) { printf( "phase=%d logical=%dx%d samples=PASS\n", phase, width, height ); fflush( stdout ); }
            Sleep( 50 );
        }
    }
    wglMakeCurrent( NULL, NULL );
    wglDeleteContext( context );
    ReleaseDC( window, dc );
    DestroyWindow( window );
    printf( "PASS resize and exit\n" );
    return 0;
}
