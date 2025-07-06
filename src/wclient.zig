const std = @import("std");
const win32 = @import("win32").everything;
const WINAPI = std.os.windows.WINAPI;
const mkutf16 = std.unicode.utf8ToUtf16LeStringLiteral;
const strings = @import("strings");
const log = @import("log");
const rdpc_session = @import("rdpc_session.zig");

const c = rdpc_session.c;

var g_allocator: std.mem.Allocator = std.heap.c_allocator;

var g_hwnd: ?win32.HWND = null;
const g_class_name = mkutf16("wclient window class");

//*****************************************************************************
// we need both WinMain and wWinMain
pub export fn WinMain(hInstance: win32.HINSTANCE,
        hPrevInstance: ?win32.HINSTANCE,
        pCmdLine: [*:0]u8, nCmdShow: u32) callconv(WINAPI) i32
{
    var len: usize = 0;
    while (pCmdLine[len] != 0) : (len += 1) { }
    if (len > 0)
    {
        const flags = win32.MB_COMPOSITE;
        var rv = win32.MultiByteToWideChar(win32.CP_UTF8, flags,
                pCmdLine, @intCast(len), null, 0);
        if (rv > 0)
        {
            const alloc_size: usize = @intCast(rv);
            var utf16 = g_allocator.alloc(u16, alloc_size + 1)
                    catch return 0;
            defer g_allocator.free(utf16);
            var utf16z = utf16[0..alloc_size :0];
            rv = win32.MultiByteToWideChar(win32.CP_UTF8, flags,
                    pCmdLine, @intCast(len), utf16z.ptr, rv);
            if (rv > 0)
            {
                const index: usize = @intCast(rv);
                utf16z[index] = 0;
                return wWinMain(hInstance, hPrevInstance,
                        utf16z.ptr, nCmdShow);
            }
        }
    }
    var noparam: [1:0]u16 = .{0};
    return wWinMain(hInstance, hPrevInstance, &noparam, nCmdShow);
}

//*****************************************************************************
pub export fn wWinMain(hInstance: win32.HINSTANCE,
        hPrevInstance: ?win32.HINSTANCE,
        pCmdLine: [*:0]u16, nCmdShow: u32) callconv(WINAPI) i32
{
    return MyWinMain(hInstance, hPrevInstance, pCmdLine, nCmdShow)
            catch return 0;
}

//*****************************************************************************
fn MyWinMain(hInstance: win32.HINSTANCE, hPrevInstance: ?win32.HINSTANCE,
        pCmdLine: [*:0]u16, nCmdShow: u32) !i32
{
    _ = hPrevInstance;
    _ = pCmdLine;

    // get temp path
    const file_name = try g_allocator.alloc(u8, 256);
    defer g_allocator.free(file_name);
    _ = try std.fmt.bufPrintZ(file_name, "c:\\temp\\wclient.log", .{});
    {
        const utf16 = try g_allocator.alloc(u16, 256);
        defer g_allocator.free(utf16);
        const utf8 = try g_allocator.alloc(u8, 256);
        defer g_allocator.free(utf8);
        const utf16z = utf16[0..utf16.len :0];
        const temp_rv = win32.GetTempPathW(@truncate(utf16z.len), utf16z.ptr);
        if (temp_rv > 0)
        {
            var al = std.ArrayList(u32).init(g_allocator);
            defer al.deinit();
            try strings.utf16_to_u32_array(std.mem.sliceTo(utf16, 0), &al);
            var bytes_written_out: usize = 0;
            try strings.u32_array_to_utf8Z(&al, utf8, &bytes_written_out);
            _ = try std.fmt.bufPrintZ(file_name, "{s}wclient.log",
                    .{std.mem.sliceTo(utf8, 0)});
        }
    }

    try log.initWithFile(&g_allocator, log.LogLevel.debug,
            std.mem.sliceTo(file_name, 0));
    defer log.deinit();
    try log.logln(log.LogLevel.info, @src(),
            "starting up, pid {}",
            .{std.os.windows.GetCurrentProcessId()});

    try rdpc_session.init();
    defer rdpc_session.deinit();

    var wc = std.mem.zeroes(win32.WNDCLASSW);
    wc.hInstance = hInstance;
    wc.lpfnWndProc = WindowProc;
    wc.lpszClassName = g_class_name;
    wc.hCursor = win32.LoadCursorW(null, win32.IDC_ARROW);
    wc.hbrBackground = win32.GetSysColorBrush(@intFromEnum(win32.COLOR_BTNFACE));
    const atom = win32.RegisterClassW(&wc);
    if (atom == 0)
    {
        return 0;
    }
    errdefer _ = win32.UnregisterClassW(g_class_name, hInstance);

    var icex = std.mem.zeroes(win32.INITCOMMONCONTROLSEX);
    icex.dwSize = @sizeOf(win32.INITCOMMONCONTROLSEX);
    icex.dwICC = win32.ICC_WIN95_CLASSES;
    if (win32.InitCommonControlsEx(&icex) == win32.FALSE)
    {
        return 0;
    }

    const hwnd = win32.CreateWindowExW(win32.WS_EX_APPWINDOW,
            g_class_name, mkutf16("wclient"),
            win32.WS_OVERLAPPEDWINDOW,
            win32.CW_USEDEFAULT, win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT, win32.CW_USEDEFAULT,
            null, null, hInstance, null);
    if (hwnd) |ahwnd|
    {
        g_hwnd = ahwnd;
    }
    else
    {
        return 0;
    }

    //const alloc_buf = std.fmt.allocPrintZ(g_allocator, "nCmdShow {}", .{nCmdShow}) catch return 0;
    //_ = win32.MessageBoxA(null, alloc_buf, "Hello Zig!", win32.MB_OKCANCEL);

    //_ = win32.MessageBoxW(null, pCmdLine, mkutf16("Hello Zig!"), win32.MB_OKCANCEL);

    // do not need to check result
    _ = win32.ShowWindow(g_hwnd, swc_from_u32(nCmdShow));

    var cont = true;
    while (cont)
    {
        const handle_count: usize = 0;
        var handles = std.mem.zeroes([16]?win32.HANDLE);
        if (win32.MsgWaitForMultipleObjects(handle_count, &handles,
                win32.FALSE, win32.INFINITE,
                win32.QS_ALLINPUT) == @intFromEnum(win32.WAIT_FAILED))
        {
            cont = false;
            break;
        }
        var msg = std.mem.zeroes(win32.MSG);
        while (win32.PeekMessageW(&msg, null, 0, 0, win32.PM_REMOVE) != 0)
        {
            if (msg.message == win32.WM_QUIT)
            {
                cont = false;
                break;
            }
            if (win32.IsDialogMessageW(g_hwnd, &msg) == 0)
            {
                _ = win32.TranslateMessage(&msg);
                _ = win32.DispatchMessageW(&msg);
            }
        }
    }
    
    return 0;
}

//*****************************************************************************
fn swc_from_u32(nCmdShow: u32) win32.SHOW_WINDOW_CMD
{
    const swc = switch (nCmdShow)
    {
        0 => win32.SW_HIDE,
        1 => win32.SW_SHOWNORMAL,
        2 => win32.SW_SHOWMINIMIZED,
        3 => win32.SW_SHOWMAXIMIZED,
        4 => win32.SW_SHOWNOACTIVATE,
        5 => win32.SW_SHOW,
        6 => win32.SW_MINIMIZE,
        7 => win32.SW_SHOWMINNOACTIVE,
        8 => win32.SW_SHOWNA,
        9 => win32.SW_RESTORE,
        10 => win32.SW_SHOWDEFAULT,
        11 => win32.SW_FORCEMINIMIZE,
        else => win32.SW_SHOWDEFAULT,
    };
    return swc;
}

//*****************************************************************************
fn xclient_show_window(hwnd: win32.HWND, wParam: win32.WPARAM, lParam: win32.LPARAM) bool
{
    _ = hwnd;
    _ = wParam;
    _ = lParam;
    return true;
}

//*****************************************************************************
fn xclient_close(hwnd: win32.HWND, wParam: win32.WPARAM,
        lParam: win32.LPARAM) bool
{
    _ = wParam;
    _ = lParam;
    if (win32.MessageBoxW(hwnd, mkutf16("Do You want to Exit?"),
            mkutf16("Finder"), win32.MB_YESNO) == win32.IDYES)
    {
        return true;
    }
    return false;
}

//*****************************************************************************
fn WindowProc(hwnd: win32.HWND, uMsg: u32, wParam: win32.WPARAM,
        lParam: win32.LPARAM) callconv(WINAPI) win32.LRESULT
{
    if (uMsg == win32.WM_DESTROY)
    {
        win32.PostQuitMessage(0);
        return 0;
    }
    const do_def = switch (uMsg)
    {
        win32.WM_SHOWWINDOW => xclient_show_window(hwnd, wParam, lParam),
        win32.WM_CLOSE => xclient_close(hwnd, wParam, lParam),
        else => true,
    };
    if (do_def)
    {
        return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
    }
    return 0;
}
