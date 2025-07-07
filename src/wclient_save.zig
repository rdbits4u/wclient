const std = @import("std");
const win = std.os.windows;
const win32 = @import("win32").everything;

//const win32 = struct {
//    usingnamespace @import("win32").zig;
//    usingnamespace @import("win32").foundation;
//    usingnamespace @import("win32").system.system_services;
//    usingnamespace @import("win32").ui.windows_and_messaging;
//    usingnamespace @import("win32").graphics.gdi;
//};

//const HINSTANCE = win32.HINSTANCE;
//const HWND = win.HWND;

//pub const UINT = c_uint;
//pub const CHAR = u8;
//pub const LPCSTR = [*c]const CHAR;

//extern fn MessageBoxA(hWnd: HWND, lpText: LPCSTR, lpCaption: LPCSTR, uType: UINT) c_int;
//extern "user32" fn MessageBoxA(?HWND, [*:0]const u8, [*:0]const u8, u32) callconv(win.WINAPI) i32;
//extern fn MessageBoxA(?WND, [*:0]const u8, [*:0]const u8, u32) callconv(win.WINAPI) c_int;

pub export fn WinMain(hInstance: win32.HINSTANCE, hPrevInstance: ?win32.HINSTANCE, 
  pCmdLine: [*:0]u16, nCmdShow: u32) callconv(win.WINAPI) i32 {
    return wWinMain(hInstance, hPrevInstance, pCmdLine, nCmdShow);
//   return 0;
}

//*****************************************************************************
//pub fn main() !void
//{
//}

pub export fn wWinMain(hInstance: win32.HINSTANCE, hPrevInstance: ?win32.HINSTANCE, 
  pCmdLine: [*:0]u16, nCmdShow: u32) callconv(win.WINAPI) i32 {

  _ = hInstance;
  _ = hPrevInstance;
  _ = pCmdLine;
  _ = nCmdShow;

  _ = win32.MessageBoxA(null, "Zig run -lc tstwnd.zig", "Hello Zig!", win32.MB_OKCANCEL);

  //_ = MessageBoxA(null, "Zig run -lc tstwnd.zig", "Hello Zig!", 0);

  return 0;
}