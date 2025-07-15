const std = @import("std");
const builtin = @import("builtin");
const strings = @import("strings");
const log = @import("log");
const hexdump = @import("hexdump");

const WINAPI = std.os.windows.WINAPI;
const mkutf16 = std.unicode.utf8ToUtf16LeStringLiteral;
pub const win32 = struct
{
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").storage.file_system;
    usingnamespace @import("win32").globalization;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").ui.controls;
    usingnamespace @import("win32").graphics.gdi;
    usingnamespace @import("win32").system.windows_programming;
    usingnamespace @import("win32").networking.win_sock;
    usingnamespace @import("win32").system.threading;
};

const c = rdpc_session.c;

const rdpc_session = @import("rdpc_session.zig");

pub const Win32Error = error
{
    CreateWindow,
};

//*****************************************************************************
pub inline fn err_if(b: bool, err: Win32Error) !void
{
    if (b) return err else return;
}

const g_class_name = mkutf16("wclient window class");

pub const rdp_win32_t = struct
{
    session: *rdpc_session.rdp_session_t,
    allocator: *const std.mem.Allocator,
    hInstance: win32.HINSTANCE,
    nCmdShow: u32,

    width: c_uint = 0,
    height: c_uint = 0,

    hwnd: ?win32.HWND = null,

    //*************************************************************************
    pub fn create(session: *rdpc_session.rdp_session_t,
            allocator: *const std.mem.Allocator,
            hInstance: win32.HINSTANCE, nCmdShow: u32,
            width: u16, height: u16) !*rdp_win32_t
    {
        const self = try allocator.create(rdp_win32_t);
        errdefer allocator.destroy(self);
        self.* = .{.session = session, .allocator = allocator,
                .hInstance = hInstance, .nCmdShow = nCmdShow};
        self.width = width;
        self.height = height;

        // create window
        try self.create_window();
        return self;
    }

    //*************************************************************************
    pub fn delete(self: *rdp_win32_t) void
    {
        self.allocator.destroy(self);
    }

    //*************************************************************************
    pub fn check_fds(self: *rdp_win32_t) !bool
    {
        try self.session.logln_devel(log.LogLevel.debug, @src(), "", .{});

        var msg = std.mem.zeroes(win32.MSG);
        while (win32.PeekMessageW(&msg, null, 0, 0, win32.PM_REMOVE) != win32.FALSE)
        {
            if (msg.message == win32.WM_QUIT)
            {
                return false;
            }
            if (win32.IsDialogMessageW(self.hwnd, &msg) == win32.FALSE)
            {
                _ = win32.TranslateMessage(&msg);
                _ = win32.DispatchMessageW(&msg);
            }
        }
        return true;
    }

    //*************************************************************************
    fn create_window(self: *rdp_win32_t) !void
    {
        try self.session.logln(log.LogLevel.debug, @src(), "", .{});
        var wc = std.mem.zeroes(win32.WNDCLASSW);
        wc.hInstance = self.hInstance;
        wc.lpfnWndProc = window_proc;
        wc.lpszClassName = g_class_name;
        wc.hCursor = win32.LoadCursorW(null, win32.IDC_ARROW);
        const color = @intFromEnum(win32.COLOR_BTNFACE);
        wc.hbrBackground = win32.GetSysColorBrush(color);
        const atom = win32.RegisterClassW(&wc);
        if (atom == 0)
        {
            return Win32Error.CreateWindow;
        }
        errdefer _ = win32.UnregisterClassW(g_class_name, self.hInstance);

        var icex = std.mem.zeroes(win32.INITCOMMONCONTROLSEX);
        icex.dwSize = @sizeOf(win32.INITCOMMONCONTROLSEX);
        icex.dwICC = win32.ICC_WIN95_CLASSES;
        if (win32.InitCommonControlsEx(&icex) == win32.FALSE)
        {
            return Win32Error.CreateWindow;
        }

        const hwnd = win32.CreateWindowExW(win32.WS_EX_APPWINDOW,
                g_class_name, mkutf16("wclient"),
                win32.WS_OVERLAPPEDWINDOW,
                win32.CW_USEDEFAULT, win32.CW_USEDEFAULT,
                win32.CW_USEDEFAULT, win32.CW_USEDEFAULT,
                null, null, self.hInstance, null);
        if (hwnd) |ahwnd|
        {
            self.hwnd = ahwnd;
            const user_usize: usize = @intFromPtr(self);
            const user_isize: isize = @bitCast(user_usize);
            _ = if (builtin.target.cpu.arch == .x86)
                    win32.SetWindowLongW(ahwnd, win32.GWLP_USERDATA,
                            user_isize) else
                    win32.SetWindowLongPtrW(ahwnd, win32.GWLP_USERDATA,
                            user_isize);
        }
        else
        {
            return Win32Error.CreateWindow;
        }

        // do not need to check result
        _ = win32.ShowWindow(self.hwnd, swc_from_u32(self.nCmdShow));

    }

    //*************************************************************************
    fn wm_close(self: *rdp_win32_t, hwnd: win32.HWND, wParam: win32.WPARAM,
            lParam: win32.LPARAM) bool
    {
        _ = self;
        _ = wParam;
        _ = lParam;
        if (win32.MessageBoxW(hwnd, mkutf16("Do You want to Exit?"),
                mkutf16("Finder"), win32.MB_YESNO) == win32.IDYES)
        {
            return true;
        }
        return false;
    }

    //*************************************************************************
    fn wm_showwindow(self: *rdp_win32_t, hwnd: win32.HWND,
            wParam: win32.WPARAM, lParam: win32.LPARAM) bool
    {
        _ = self;
        _ = hwnd;
        _ = wParam;
        _ = lParam;
        return true;
    }

};

//*****************************************************************************
fn window_proc(hwnd: win32.HWND, uMsg: u32, wParam: win32.WPARAM,
        lParam: win32.LPARAM) callconv(WINAPI) win32.LRESULT
{
    if (uMsg == win32.WM_DESTROY)
    {
        win32.PostQuitMessage(0);
        return 0;
    }
    const user_isize: isize = if (builtin.target.cpu.arch == .x86)
            win32.GetWindowLongW(hwnd, win32.GWLP_USERDATA) else
            win32.GetWindowLongPtrW(hwnd, win32.GWLP_USERDATA);
    const user_usize: usize = @bitCast(user_isize);
    const self: ?*rdp_win32_t = @ptrFromInt(user_usize);
    var do_def = true;
    if (self) |aself|
    {
        do_def = switch (uMsg)
        {
            win32.WM_CLOSE => aself.wm_close(hwnd, wParam, lParam),
            win32.WM_SHOWWINDOW => aself.wm_showwindow(hwnd, wParam, lParam),
            else => true,
        };
    }
    if (do_def)
    {
        return win32.DefWindowProcW(hwnd, uMsg, wParam, lParam);
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
