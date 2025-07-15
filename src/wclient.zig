const std = @import("std");
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

var g_allocator: std.mem.Allocator = std.heap.c_allocator;

const MyError = error
{
    ShowCommandLine,
};

var g_hwnd: ?win32.HWND = null;
const g_class_name = mkutf16("wclient window class");

//*****************************************************************************
fn show_command_line_args() !void
{
}

//*****************************************************************************
fn process_server_port(rdp_connect: *rdpc_session.rdp_connect_t,
        slice_arg: []const u16) !void
{
    var al_u32 = std.ArrayList(u32).init(g_allocator);
    defer al_u32.deinit();

    if (slice_arg.len < 1)
    {
        return;
    }

    // look for \\.\pipe\pipename
    const dst: []u8 = if (slice_arg[0] == '\\')
            &rdp_connect.server_port else &rdp_connect.server_name;
    try strings.utf16_to_utf8Z(&al_u32, dst, slice_arg);

    const sep1 = std.mem.lastIndexOfLinear(u16, slice_arg, mkutf16(":"));
    const sep2 = std.mem.lastIndexOfLinear(u16, slice_arg, mkutf16("]"));
    const sep3 = std.mem.lastIndexOfLinear(u16, slice_arg, mkutf16("["));
    while (true) : (break)
    {
        if (sep1) |asep1| // look for [aaaa:bbbb:cccc:dddd]:3389
        {
            if (sep2) |asep2|
            {
                if (sep3) |asep3|
                {
                    if (asep1 > asep2)
                    {
                        const s = slice_arg[asep3 + 1..asep2];
                        const p = slice_arg[asep1 + 1..];
                        try strings.utf16_to_utf8Z(&al_u32, &rdp_connect.server_name, s);
                        try strings.utf16_to_utf8Z(&al_u32, &rdp_connect.server_port, p);
                        break;
                    }
                }
            }
        }
        if (sep2) |asep2| // look for [aaaa:bbbb:cccc:dddd]
        {
            if (sep3) |asep3|
            {
                const s = slice_arg[asep3 + 1..asep2];
                try strings.utf16_to_utf8Z(&al_u32, &rdp_connect.server_name, s);
                break;
            }
        }
        if (sep1) |asep1| // look for 127.0.0.1:3389
        {
            const s = slice_arg[0..asep1];
            const p = slice_arg[asep1 + 1..];
            try strings.utf16_to_utf8Z(&al_u32, &rdp_connect.server_name, s);
            try strings.utf16_to_utf8Z(&al_u32, &rdp_connect.server_port, p);
            break;
        }
    }
}

//*****************************************************************************
fn process_args(pCmdLine: [*:0]u16, settings: *c.rdpc_settings_t,
        rdp_connect: *rdpc_session.rdp_connect_t) !void
{
    // default some stuff
    strings.copyZ(&rdp_connect.server_port, "3389");
    settings.bpp = 32;
    settings.width = 1024;
    settings.height = 768;
    settings.dpix = 96;
    settings.dpiy = 96;
    settings.keyboard_layout = 0x0409;
    settings.rfx = 1;
    settings.jpg = 0;
    settings.use_frame_ack = 1;
    settings.frames_in_flight = 5;
    var al_u32 = std.ArrayList(u32).init(g_allocator);
    defer al_u32.deinit();
    // get some info from os
    var cb_buffer: u32 = 256;
    const buffer = try g_allocator.alloc(u16, cb_buffer);
    defer g_allocator.free(buffer);
    const bufferZ = buffer[0.. :0];
    if (win32.GetUserNameW(bufferZ.ptr, &cb_buffer) != win32.FALSE)
    {
        try strings.utf16_to_utf8Z(&al_u32, &settings.username,
                std.mem.sliceTo(bufferZ, 0));
        try log.logln(log.LogLevel.info, @src(), "username {s}",
                .{std.mem.sliceTo(&settings.username, 0)});
    }
    cb_buffer = 256;
    if (win32.GetComputerNameW(bufferZ.ptr, &cb_buffer) != win32.FALSE)
    {
        try strings.utf16_to_utf8Z(&al_u32, &settings.clientname,
                std.mem.sliceTo(bufferZ, 0));
        try log.logln(log.LogLevel.info, @src(), "clientname {s}",
                .{std.mem.sliceTo(&settings.clientname, 0)});
    }
    // process command line args
    var al = std.ArrayList([]const u16).init(g_allocator);
    defer al.deinit();
    var it = std.mem.tokenizeSequence(u16, std.mem.sliceTo(pCmdLine, 0),
            mkutf16(" "));
    while (it.next()) |param|
    {
        try al.append(param);
    }
    var index: usize = 0;
    const count = al.items.len;
    while (index < count) : (index += 1)
    {
        var slice_arg = al.items[index];
        try log.logln(log.LogLevel.info, @src(), "{} {} {any}",
                .{index, count, slice_arg});
        if (std.mem.eql(u16, slice_arg, mkutf16("-h")))
        {
            return MyError.ShowCommandLine;
        }
        else if (std.mem.eql(u16, slice_arg, mkutf16("-u")))
        {
            if (index + 1 >= count)
            {
                return MyError.ShowCommandLine;
            }
            index += 1;
            slice_arg = al.items[index];
            try strings.utf16_to_utf8Z(&al_u32, &settings.username, slice_arg);
        }
        else if (std.mem.eql(u16, slice_arg, mkutf16("-d")))
        {
            if (index + 1 >= count)
            {
                return MyError.ShowCommandLine;
            }
            index += 1;
            slice_arg = al.items[index];
            try strings.utf16_to_utf8Z(&al_u32, &settings.domain, slice_arg);
        }
        else if (std.mem.eql(u16, slice_arg, mkutf16("-s")))
        {
            if (index + 1 >= count)
            {
                return MyError.ShowCommandLine;
            }
            index += 1;
            slice_arg = al.items[index];
            try strings.utf16_to_utf8Z(&al_u32, &settings.altshell, slice_arg);
        }
        else if (std.mem.eql(u16, slice_arg, mkutf16("-c")))
        {
            if (index + 1 >= count)
            {
                return MyError.ShowCommandLine;
            }
            index += 1;
            slice_arg = al.items[index];
            try strings.utf16_to_utf8Z(&al_u32, &settings.workingdir, slice_arg);
        }
        else if (std.mem.eql(u16, slice_arg, mkutf16("-p")))
        {
            if (index + 1 >= count)
            {
                return MyError.ShowCommandLine;
            }
            index += 1;
            slice_arg = al.items[index];
            try strings.utf16_to_utf8Z(&al_u32, &settings.password, slice_arg);
        }
        else if (std.mem.eql(u16, slice_arg, mkutf16("-n")))
        {
            if (index + 1 >= count)
            {
                return MyError.ShowCommandLine;
            }
            index += 1;
            slice_arg = al.items[index];
            try strings.utf16_to_utf8Z(&al_u32, &settings.clientname, slice_arg);
        }
        else if (std.mem.eql(u16, slice_arg, mkutf16("-g")))
        {
            if (index + 1 >= count)
            {
                return MyError.ShowCommandLine;
            }
            index += 1;
            slice_arg = al.items[index];
            var seq = std.mem.tokenizeSequence(u16, slice_arg, mkutf16("x"));
            if (seq.next()) |chunk0|
            {
                settings.width =
                    try std.fmt.parseIntWithGenericCharacter(c_int, u16,
                    chunk0, 10);
                if (seq.next()) |chunk1|
                {
                    settings.height =
                        try std.fmt.parseIntWithGenericCharacter(c_int, u16,
                        chunk1, 10);
                }
                else
                {
                    return MyError.ShowCommandLine;
                }
            }
            else
            {
                return MyError.ShowCommandLine;
            }
        }
        else
        {
            try process_server_port(rdp_connect, slice_arg);
        }
    }
}

//*****************************************************************************
fn create_rdpc_session(pCmdLine: [*:0]u16,
        rdp_connect: *rdpc_session.rdp_connect_t,
        hInstance: win32.HINSTANCE,
        nCmdShow: u32) !*rdpc_session.rdp_session_t
{
    const settings = try g_allocator.create(c.struct_rdpc_settings_t);
    defer g_allocator.destroy(settings);
    settings.* = .{};
    const result = process_args(pCmdLine, settings, rdp_connect);
    if (result) |_| { } else |err|
    {
        if (err == MyError.ShowCommandLine)
        {
            try show_command_line_args();
        }
        return err;
    }
    return try rdpc_session.rdp_session_t.create(&g_allocator,
            settings, rdp_connect, hInstance, nCmdShow);
}

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

    // init logging
    try log.initWithFile(&g_allocator, log.LogLevel.debug,
            std.mem.sliceTo(file_name, 0));
    defer log.deinit();
    try log.logln(log.LogLevel.info, @src(),
            "starting up, pid {}",
            .{std.os.windows.GetCurrentProcessId()});

    try rdpc_session.init();
    defer rdpc_session.deinit();

    const rdp_connect = try g_allocator.create(rdpc_session.rdp_connect_t);
    defer g_allocator.destroy(rdp_connect);
    rdp_connect.* = .{};

    const session = create_rdpc_session(pCmdLine, rdp_connect, hInstance,
            nCmdShow) catch |err| if (err == MyError.ShowCommandLine)
            return 0 else return err;
    defer session.delete();
    try session.connect();
    try session.loop();
    return 0;
}
