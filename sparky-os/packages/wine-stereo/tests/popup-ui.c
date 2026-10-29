/* SPDX-License-Identifier: MIT */
/* Small interactive fixture for Wine's X11 popup metadata and ordinary UI. */
#include <windows.h>
#include <commctrl.h>
#include <stdio.h>
#include <string.h>

enum { CMD_COMBO = WM_APP + 1, CMD_MENUBAR, CMD_RIGHT, CMD_CLOSE_MENU, CMD_CONTEXT, CMD_TOOLTIP, CMD_DIALOG, CMD_RESIZE, CMD_FINISH, CMD_SELECT };
static HWND main_window, combo, tooltip, dialog;
static HMENU context_menu;
static TOOLINFOA tool;

static void key( WORD code )
{
    INPUT input[2] = {{0}};
    input[0].type = input[1].type = INPUT_KEYBOARD;
    input[0].ki.wVk = input[1].ki.wVk = code;
    input[1].ki.dwFlags = KEYEVENTF_KEYUP;
    if (SendInput( 2, input, sizeof(INPUT) ) != 2) ExitProcess( 10 );
}

static DWORD WINAPI commands( void *unused )
{
    char command[32];
    static const char *names[] = {"combo", "menubar", "right", "close", "context", "tooltip", "dialog", "resize", "exit", "select"};
    unsigned i;
    (void)unused;
    while (scanf( "%31s", command ) == 1)
        for (i = 0; i < sizeof(names) / sizeof(names[0]); ++i)
            if (!strcmp( command, names[i] )) PostMessageA( main_window, CMD_COMBO + i, 0, 0 );
    return 0;
}

static LRESULT CALLBACK window_proc( HWND window, UINT message, WPARAM wparam, LPARAM lparam )
{
    switch (message)
    {
    case WM_TIMER:
        InvalidateRect( window, NULL, FALSE );
        return 0;
    case WM_PAINT:
    {
        PAINTSTRUCT paint;
        RECT rect;
        HDC dc = BeginPaint( window, &paint );
        HBRUSH brush = CreateSolidBrush( RGB(32, 64, 96) );
        GetClientRect( window, &rect );
        FillRect( dc, &rect, brush );
        DeleteObject( brush );
        SetBkMode( dc, TRANSPARENT );
        SetTextColor( dc, RGB(255, 255, 255) );
        TextOutA( dc, 20, 16, "Ordinary Wine UI", 16 );
        EndPaint( window, &paint );
        return 0;
    }
    case CMD_COMBO:
        SendMessageA( combo, CB_SHOWDROPDOWN, TRUE, 0 );
        break;
    case CMD_MENUBAR:
        SendMessageA( combo, CB_SHOWDROPDOWN, FALSE, 0 );
        SetForegroundWindow( window );
        SendMessageA( window, WM_SYSCOMMAND, SC_KEYMENU, 'f' );
        break;
    case CMD_RIGHT:
        key( VK_RIGHT );
        break;
    case CMD_SELECT:
        key( VK_RETURN );
        break;
    case CMD_CLOSE_MENU:
        EndMenu();
        SendMessageA( combo, CB_SHOWDROPDOWN, FALSE, 0 );
        SendMessageA( tooltip, TTM_TRACKACTIVATE, FALSE, (LPARAM)&tool );
        if (dialog) { DestroyWindow( dialog ); dialog = NULL; }
        break;
    case CMD_CONTEXT:
        SetForegroundWindow( window );
        TrackPopupMenu( context_menu, TPM_LEFTALIGN, 170, 170, 0, window, NULL );
        break;
    case CMD_TOOLTIP:
        SendMessageA( tooltip, TTM_TRACKPOSITION, 0, MAKELPARAM(210, 220) );
        SendMessageA( tooltip, TTM_TRACKACTIVATE, TRUE, (LPARAM)&tool );
        break;
    case CMD_DIALOG:
        dialog = CreateWindowA( "WinePopupUi", "Owned dialog", WS_POPUP | WS_CAPTION | WS_SYSMENU | WS_VISIBLE,
                                450, 300, 180, 100, window, NULL, GetModuleHandleA( NULL ), NULL );
        if (!dialog || GetWindow( dialog, GW_OWNER ) != window) ExitProcess( 11 );
        break;
    case CMD_RESIZE:
        SetWindowPos( window, NULL, 0, 0, 360, 260, SWP_NOMOVE | SWP_NOZORDER );
        break;
    case CMD_FINISH:
    case WM_CLOSE:
        DestroyWindow( window );
        break;
    case WM_DESTROY:
        if (window == main_window) PostQuitMessage( 0 );
        break;
    case WM_COMMAND:
        printf( "command=%u recipient=main\n", LOWORD(wparam) );
        fflush( stdout );
        break;
    default:
        return DefWindowProcA( window, message, wparam, lparam );
    }
    return 0;
}

int main(void)
{
    WNDCLASSA cls = {0};
    INITCOMMONCONTROLSEX controls = {sizeof(controls), ICC_WIN95_CLASSES};
    HMENU bar, dropdown, nested;
    HANDLE reader;
    MSG message;
    BOOL wow64 = FALSE;
    InitCommonControlsEx( &controls );
    cls.lpfnWndProc = window_proc;
    cls.hInstance = GetModuleHandleA( NULL );
    cls.lpszClassName = "WinePopupUi";
    cls.hCursor = LoadCursorA( NULL, IDC_ARROW );
    if (!RegisterClassA( &cls )) return 2;
    bar = CreateMenu(); dropdown = CreatePopupMenu(); nested = CreatePopupMenu();
    AppendMenuA( nested, MF_STRING, 101, "Nested command" );
    AppendMenuA( dropdown, MF_POPUP, (UINT_PTR)nested, "Nested" );
    AppendMenuA( dropdown, MF_STRING, 102, "Plain command" );
    AppendMenuA( bar, MF_POPUP, (UINT_PTR)dropdown, "&File" );
    context_menu = CreatePopupMenu();
    AppendMenuA( context_menu, MF_STRING, 103, "Context command" );
    main_window = CreateWindowA( cls.lpszClassName, "Wine popup UI fixture", WS_OVERLAPPEDWINDOW | WS_VISIBLE | WS_CLIPCHILDREN,
                                 40, 40, 400, 300, NULL, bar, cls.hInstance, NULL );
    if (!main_window) return 3;
    SetTimer( main_window, 1, 100, NULL );
    combo = CreateWindowA( "COMBOBOX", "", WS_CHILD | WS_VISIBLE | CBS_DROPDOWNLIST,
                           20, 48, 170, 120, main_window, (HMENU)201, cls.hInstance, NULL );
    SendMessageA( combo, CB_ADDSTRING, 0, (LPARAM)"First item" );
    SendMessageA( combo, CB_ADDSTRING, 0, (LPARAM)"Second item" );
    SendMessageA( combo, CB_SETCURSEL, 0, 0 );
    tooltip = CreateWindowExA( WS_EX_TOPMOST, TOOLTIPS_CLASSA, NULL, WS_POPUP | TTS_ALWAYSTIP | TTS_NOPREFIX,
                               0, 0, 0, 0, main_window, NULL, cls.hInstance, NULL );
    tool.cbSize = sizeof(tool); tool.uFlags = TTF_TRACK | TTF_ABSOLUTE;
    tool.hwnd = main_window; tool.uId = 1; tool.lpszText = "Ordinary tooltip";
    if (!SendMessageA( tooltip, TTM_ADDTOOLA, 0, (LPARAM)&tool )) return 4;
    reader = CreateThread( NULL, 0, commands, NULL, 0, NULL );
    if (!reader) return 5;
    CloseHandle( reader );
    IsWow64Process( GetCurrentProcess(), &wow64 );
    printf( "READY pointer_bits=%u wow64=%d\n", (unsigned)(sizeof(void *) * 8), wow64 );
    fflush( stdout );
    while (GetMessageA( &message, NULL, 0, 0 ) > 0)
    {
        TranslateMessage( &message );
        DispatchMessageA( &message );
    }
    DestroyMenu( context_menu );
    puts( "PASS exit" );
    return 0;
}
