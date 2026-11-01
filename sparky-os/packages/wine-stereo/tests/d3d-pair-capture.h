/* SPDX-License-Identifier: MIT */
/* Keep the window responsive while the observer captures this exact Present. */
static DWORD WINAPI pair_capture_reply(void *unused)
{
    char line[32];
    (void)unused;
    return fgets(line, sizeof(line), stdin) ? 0 : 91;
}

static void pair_capture(int phase, int width, int height)
{
    DWORD status, start = GetTickCount();
    HANDLE reader = CreateThread(NULL, 0, pair_capture_reply, NULL, 0, NULL);
    if (!reader) ExitProcess(92);
    printf("phase=%d logical=%dx%d frame=ready presents=%d\n", phase, width, height, phase + 1);
    fflush(stdout);
    for (;;)
    {
        MSG message;
        DWORD wait = MsgWaitForMultipleObjectsEx(1, &reader, 10, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
        if (wait == WAIT_OBJECT_0) break;
        if (wait == WAIT_FAILED || GetTickCount() - start > 30000) ExitProcess(94);
        while (PeekMessageA(&message, NULL, 0, 0, PM_REMOVE))
        {
            TranslateMessage(&message);
            DispatchMessageA(&message);
        }
    }
    if (!GetExitCodeThread(reader, &status)) ExitProcess(95);
    CloseHandle(reader);
    if (status) ExitProcess(status);
    printf("capture_done phase=%d presents=%d\n", phase, phase + 1);
    fflush(stdout);
}
