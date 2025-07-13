const std = @import("std");
const strings = @import("strings");
const log = @import("log");
const hexdump = @import("hexdump");
const rdpc_win32 = @import("rdpc_win32.zig");

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

pub const c = @cImport(
{
    @cInclude("librdpc.h");
    @cInclude("libsvc.h");
    @cInclude("libcliprdr.h");
    @cInclude("librdpsnd.h");
});

const SesError = error
{
    RfxDecoderCreate,
    LookupAddress,
    Connect,
    RdpcProcessServerData,
    RdpcStart,
    RdpcCreate,
    RdpcInit,
    SvcInit,
    SvcCreate,
    CliprdrInit,
    CliprdrCreate,
    RdpsndInit,
    RdpsndCreate,
};

//*****************************************************************************
pub inline fn err_if(b: bool, err: SesError) !void
{
    if (b) return err else return;
}

// for storing left over data for server
const send_t = struct
{
    sent: usize = 0,
    out_data_slice: []u8,
    next: ?*send_t = null,
};

pub const rdp_connect_t = struct
{
    server_name: [512]u8 = std.mem.zeroes([512]u8),
    server_port: [64]u8 = std.mem.zeroes([64]u8),
};

pub const rdp_session_t = struct
{
    allocator: *const std.mem.Allocator,
    rdp_connect: *rdp_connect_t,
    rdpc: *c.rdpc_t,
    svc: *c.svc_channels_t,
    hInstance: win32.HINSTANCE,
    nCmdShow: u32,

    connected: bool = false,
    sck: win32.SOCKET = win32.INVALID_SOCKET,
    recv_start: usize = 0,
    in_data_slice: []u8 = &.{},

    send_head: ?*send_t = null,
    send_tail: ?*send_t = null,

    rdp_win32: ?*rdpc_win32.rdp_win32_t = null,

    //*************************************************************************
    pub fn create(allocator: *const std.mem.Allocator,
            settings: *c.rdpc_settings_t,
            rdp_connect: *rdp_connect_t,
            hInstance: win32.HINSTANCE, nCmdShow: u32) !*rdp_session_t
    {
        const self = try allocator.create(rdp_session_t);
        errdefer allocator.destroy(self);

        // setup rdpc
        var rdpc = try create_rdpc(settings);
        errdefer _ = c.rdpc_delete(rdpc);
        rdpc.user = self;
        rdpc.log_msg = cb_rdpc_log_msg;
        rdpc.send_to_server = cb_rdpc_send_to_server;
        rdpc.set_surface_bits = cb_rdpc_set_surface_bits;
        rdpc.frame_marker = cb_rdpc_frame_marker;
        rdpc.pointer_update = cb_rdpc_pointer_update;
        rdpc.pointer_cached = cb_rdpc_pointer_cached;
        rdpc.channel = cb_rdpc_channel;

        // setup svc
        var svc = try create_svc();
        errdefer _ = c.svc_delete(svc);
        svc.user = self;
        svc.log_msg = cb_svc_log_msg;
        svc.send_data = cb_svc_send_data;

        // init self
        self.* = .{.allocator = allocator, .rdp_connect = rdp_connect,
                .hInstance = hInstance, .nCmdShow = nCmdShow, .rdpc = rdpc,
                .svc = svc};
        return self;
    }

    //*************************************************************************
    pub fn delete(self: *rdp_session_t) void
    {
        self.allocator.destroy(self);
    }

    //*************************************************************************
    pub fn logln(self: *rdp_session_t, lv: log.LogLevel,
            src: std.builtin.SourceLocation,
            comptime fmt: []const u8, args: anytype) !void
    {
        _ = self;
        try log.logln(lv, src, fmt, args);
    }

    //*************************************************************************
    pub fn logln_devel(self: *rdp_session_t, lv: log.LogLevel,
            src: std.builtin.SourceLocation,
            comptime fmt: []const u8, args: anytype) !void
    {
        _ = self;
        try log.logln_devel(lv, src, fmt, args);
    }

    //*************************************************************************
    // data to the rdp server
    fn send_slice_to_server(self: *rdp_session_t, data: []u8) !void
    {
        var slice = data[0.. :0];
        if (self.send_head == null)
        {
            // try to send
            const flags = std.mem.zeroes(win32.SEND_RECV_FLAGS);
            const sent = win32.send(self.sck,
                    slice.ptr,
                    @intCast(slice.len), flags);
            if (sent > 0)
            {
                if (sent >= slice.len)
                {
                    // all sent, ok
                    return;
                }
                const sent_usize: usize = @intCast(sent);
                slice = slice[sent_usize..];
            }
            else if (sent == win32.SOCKET_ERROR)
            {
                const last_error = win32.WSAGetLastError();
                if (last_error == win32.WSAEWOULDBLOCK)
                {
                    // ok
                }
                else
                {
                    return SesError.Connect;
                }
            }
        }
        // save any left over data to send later
        const out_data_slice = try self.allocator.alloc(u8, slice.len);
        errdefer self.allocator.free(out_data_slice);
        const send: *send_t = try self.allocator.create(send_t);
        errdefer self.allocator.destroy(send);
        send.* = .{.out_data_slice = out_data_slice};
        std.mem.copyForwards(u8, send.out_data_slice, slice);
        if (self.send_tail) |asend_tail|
        {
            asend_tail.next = send;
            self.send_tail = send;
        }
        else
        {
            self.send_head = send;
            self.send_tail = send;
        }
    }

    //*************************************************************************
    fn set_surface_bits(self: *rdp_session_t,
            bitmap_data: *c.bitmap_data_t) !void
    {
        try self.logln(log.LogLevel.info, @src(),
                "bits_per_pixel {}",
                .{bitmap_data.bits_per_pixel});
    }

    //*************************************************************************
    fn frame_marker(self: *rdp_session_t, frame_action: u16,
            frame_id: u32) !void
    {
        try self.logln(log.LogLevel.info, @src(),
                "frame_action {} frame_id {}", .{frame_action, frame_id});
        if (frame_action == c.SURFACECMD_FRAMEACTION_END)
        {
            const rv = c.rdpc_send_frame_ack(self.rdpc, frame_id);
            _ = rv;
        }
    }

    //*************************************************************************
    fn pointer_update(self: *rdp_session_t, pointer: *c.pointer_t) !void
    {
        try self.logln(log.LogLevel.info, @src(), "bpp {}",
                .{pointer.xor_bpp});
        // if (self.rdp_x11) |ardp_x11|
        // {
        //     try ardp_x11.pointer_update(pointer);
        // }
    }

    //*************************************************************************
    fn pointer_cached(self: *rdp_session_t, cache_index: u16) !void
    {
        try self.logln_devel(log.LogLevel.info, @src(), "cache_index {}",
                .{cache_index});
        // if (self.rdp_x11) |ardp_x11|
        // {
        //     try ardp_x11.pointer_cached(cache_index);
        // }
    }

    //*************************************************************************
    pub fn connect(self: *rdp_session_t) !void
    {
        // init winsock
        var wsadata = std.mem.zeroes(win32.WSAData);
        if (win32.WSAStartup(2, &wsadata) != 0)
        {
            return SesError.Connect;
        }
        errdefer _ = win32.WSACleanup();
        const server = std.mem.sliceTo(&self.rdp_connect.server_name, 0);
        const port = std.mem.sliceTo(&self.rdp_connect.server_port, 0);
        // create socket
        self.sck = win32.socket(@intFromEnum(win32.AF_INET),
                win32.SOCK_STREAM, @intFromEnum(win32.IPPROTO_TCP));
        if (self.sck == win32.INVALID_SOCKET)
        {
            return SesError.Connect;
        }
        errdefer _ = win32.closesocket(self.sck);
        // set non blocking
        var i: u32 = 1;
        if (win32.ioctlsocket(self.sck,
                win32.FIONBIO, &i) == win32.SOCKET_ERROR)
        {
            return SesError.Connect;
        }
        // connect
        var s = std.mem.zeroes(win32.SOCKADDR_IN);
        s.sin_family = @intFromEnum(win32.AF_INET);
        const port_u16 = try std.fmt.parseInt(u16, port, 10);
        s.sin_port = win32.htons(port_u16);
        const serverZ = server[0.. :0];
        s.sin_addr.S_un.S_addr = win32.inet_addr(serverZ.ptr);
        if (s.sin_addr.S_un.S_addr == win32.INADDR_NONE)
        {
            const h = win32.gethostbyname(serverZ.ptr);
            if (h) |ah|
            {
                if (ah.h_name) |_|
                {
                    if (ah.h_addr_list) |ah_addr_list|
                    {
                        if (ah_addr_list.*) |aph_addr_list|
                        {
                            const ptr_i8 = aph_addr_list;
                            const ptr_u32: *u32 = @alignCast(@ptrCast(ptr_i8));
                            s.sin_addr.S_un.S_addr = ptr_u32.*;
                        }
                    }
                }
            }
        }
        const connect_error = win32.connect(self.sck, @ptrCast(&s),
                @sizeOf(win32.SOCKADDR_IN));
        if (connect_error == win32.SOCKET_ERROR)
        {
            const last_error = win32.WSAGetLastError();
            if (last_error == win32.WSAEWOULDBLOCK)
            {
                // ok
            }
            else
            {
                return SesError.Connect;
            }
        }
    }

    //*************************************************************************
    // data from the rdp server
    fn read_process_server_data(self: *rdp_session_t) !void
    {
        try self.logln_devel(log.LogLevel.info, @src(),
                "server sck is set", .{});
        const recv_slice = self.in_data_slice[self.recv_start.. :0];
        const flags = std.mem.zeroes(win32.SEND_RECV_FLAGS);
        const recv_rv = win32.recv(self.sck,
                recv_slice.ptr,
                @intCast(recv_slice.len), flags);
        try self.logln_devel(log.LogLevel.info, @src(),
                "recv_rv {} recv_start {}",
                .{recv_rv, self.recv_start});
        if (recv_rv > 0)
        {
            try err_if(self.connected == false, SesError.Connect);
            const recv_rv_usize: usize = @intCast(recv_rv);
            var end = self.recv_start + recv_rv_usize;
            while (end > 0)
            {
                const server_data_slice = self.in_data_slice[0..end];
                // bytes_processed
                var bp: u32 = 0;
                // bytes_in_buf
                const bib: u32 = @truncate(server_data_slice.len);
                const rv = c.rdpc_process_server_data(self.rdpc,
                        server_data_slice.ptr, bib, &bp);
                if (rv == c.LIBRDPC_ERROR_NONE)
                {
                    // copy any left over data up to front of in_data_slice
                    const slice = self.in_data_slice;
                    std.mem.copyForwards(u8, slice[0..], slice[bp..end]);
                    end -= bp;
                    self.recv_start = end;
                }
                else if (rv == c.LIBRDPC_ERROR_NEED_MORE)
                {
                    self.recv_start = end;
                    break;
                }
                else
                {
                    try self.logln(log.LogLevel.debug, @src(),
                            "rdpc_process_server_data error {}",
                            .{rv});
                    return SesError.RdpcProcessServerData;
                }
            }
        }
        else if (recv_rv == -1)
        {
            const last_error = win32.WSAGetLastError();
            if (last_error == win32.WSAEWOULDBLOCK)
            {
                // ok
            }
            else
            {
                return SesError.Connect;
            }
        }
    }

    //*************************************************************************
    fn process_write_server_data(self: *rdp_session_t) !void
    {
        if (self.connected == false)
        {
            self.connected = true;
            try self.logln(log.LogLevel.info, @src(), "connected set", .{});
            // connected complete, lets start
            const rv = c.rdpc_start(self.rdpc);
            if (rv != c.LIBRDPC_ERROR_NONE)
            {
                try self.logln(log.LogLevel.err,
                        @src(), "rdpc_start failed error {}",
                        .{rv});
                return SesError.RdpcStart;
            }
            const width = self.rdpc.cgcc.core.desktopWidth;
            const height = self.rdpc.cgcc.core.desktopHeight;
            try self.logln(log.LogLevel.info, @src(), "width {} height {}",
                    .{width, height});
            self.rdp_win32 = try rdpc_win32.rdp_win32_t.create(self,
                    self.allocator, self.hInstance, self.nCmdShow,
                    width, height);
        }
        if (self.send_head) |asend_head|
        {
            const send = asend_head;
            const slice = send.out_data_slice[send.sent.. :0];
            const flags = std.mem.zeroes(win32.SEND_RECV_FLAGS);
            const sent = win32.send(self.sck,
                    slice.ptr,
                    @intCast(slice.len), flags);
            if (sent > 0)
            {
                const sent_usize: usize = @intCast(sent);
                send.sent += sent_usize;
                if (send.sent >= send.out_data_slice.len)
                {
                    self.send_head = send.next;
                    if (self.send_head == null)
                    {
                        // if send_head is null, set send_tail to null
                        self.send_tail = null;
                    }
                    self.allocator.free(send.out_data_slice);
                    self.allocator.destroy(send);
                }
            }
            else if (sent == win32.SOCKET_ERROR)
            {
                const last_error = win32.WSAGetLastError();
                if (last_error == win32.WSAEWOULDBLOCK)
                {
                    // ok
                }
                else
                {
                    return SesError.Connect;
                }
            }
        }
    }

    //*************************************************************************
    // WSA_INVALID_EVENT missing
    // https://github.com/microsoft/win32metadata/issues/1587
    pub fn loop(self: *rdp_session_t) !void
    {
        try self.logln(log.LogLevel.info, @src(), "", .{});

        self.in_data_slice = try self.allocator.alloc(u8, 128 * 1024);
        defer self.allocator.free(self.in_data_slice);

        var cont = true;
        while (cont)
        {
            // read, close event
            const event1 = win32.WSACreateEvent();
            try err_if(event1 == null, SesError.Connect);
            defer _ = win32.WSACloseEvent(event1);
            _ = win32.WSAEventSelect(self.sck, event1, win32.FD_READ | win32.FD_CLOSE);
            // write event
            var event2: ?win32.HANDLE = null;
            defer if (event2) |aevent| { _ = win32.WSACloseEvent(aevent); };
            if ((self.connected == false) or (self.send_head != null))
            {
                event2 = win32.WSACreateEvent();
                try err_if(event2 == null, SesError.Connect);
                _ = win32.WSAEventSelect(self.sck, event2, win32.FD_WRITE);
            }
            // setup for MsgWaitForMultipleObjects
            var handle_count: usize = 0;
            var handles = std.mem.zeroes([16]?win32.HANDLE);
            handles[handle_count] = event1;
            handle_count += 1;
            if (event2) |aevent|
            {
                handles[handle_count] = aevent;
                handle_count += 1;
            }
            if (win32.MsgWaitForMultipleObjects(@truncate(handle_count),
                    &handles, win32.FALSE, win32.INFINITE,
                    win32.QS_ALLINPUT) == @intFromEnum(win32.WAIT_FAILED))
            {
                cont = false;
                break;
            }
            const wait_obj_0: u32 = @intFromEnum(win32.WAIT_OBJECT_0);
            if (win32.WaitForSingleObject(event1, 0) == wait_obj_0)
            {
                try self.read_process_server_data();
            }
            if (event2) |aevent|
            {
                if (win32.WaitForSingleObject(aevent, 0) == wait_obj_0)
                {
                    try self.process_write_server_data();
                }
            }
            if (self.rdp_win32) |ardp_win32|
            {
                cont = try ardp_win32.check_fds();
            }
        }
    }

    //*************************************************************************
    fn log_msg_slice(self: *rdp_session_t, msg: []const u8) !void
    {
        try self.logln(log.LogLevel.info, @src(), "[{s}]", .{msg});
    }

};

//*****************************************************************************
fn create_rdpc(settings: *c.rdpc_settings_t) !*c.rdpc_t
{
    var rdpc: ?*c.rdpc_t = null;
    const rv = c.rdpc_create(settings, &rdpc);
    if (rv == c.LIBRDPC_ERROR_NONE)
    {
        if (rdpc) |ardpc|
        {
            return ardpc;
        }
    }
    return SesError.RdpcCreate;
}

//*****************************************************************************
fn create_svc() !*c.svc_channels_t
{
    var svc: ?*c.svc_channels_t = null;
    const rv = c.svc_create(&svc);
    if (rv == c.LIBSVC_ERROR_NONE)
    {
        if (svc) |asvc|
        {
            return asvc;
        }
    }
    return SesError.SvcCreate;
}

//*****************************************************************************
fn create_cliprdr() !*c.cliprdr_t
{
    var cliprdr: ?*c.cliprdr_t = null;
    const rv = c.cliprdr_create(&cliprdr);
    if (rv == c.LIBCLIPRDR_ERROR_NONE)
    {
        if (cliprdr) |acliprdr|
        {
            return acliprdr;
        }
    }
    return SesError.CliprdrCreate;
}

//*****************************************************************************
fn create_rdpsnd() !*c.rdpsnd_t
{
    var rdpsnd: ?*c.rdpsnd_t = null;
    const rv = c.rdpsnd_create(&rdpsnd);
    if (rv == c.LIBRDPSND_ERROR_NONE)
    {
        if (rdpsnd) |ardpsnd|
        {
            return ardpsnd;
        }
    }
    return SesError.RdpsndCreate;
}

//*****************************************************************************
pub fn init() !void
{
    try err_if(c.rdpc_init() != c.LIBRDPC_ERROR_NONE, SesError.RdpcInit);
    try err_if(c.svc_init() != c.LIBSVC_ERROR_NONE, SesError.SvcInit);
    try err_if(c.cliprdr_init() != c.LIBCLIPRDR_ERROR_NONE, SesError.CliprdrInit);
    try err_if(c.rdpsnd_init() != c.LIBRDPSND_ERROR_NONE, SesError.RdpsndInit);
}

//*****************************************************************************
pub fn deinit() void
{
    _ = c.rdpc_deinit();
    _ = c.svc_deinit();
    _ = c.cliprdr_deinit();
    _ = c.rdpsnd_deinit();
}

//*****************************************************************************
// callback
// int (*log_msg)(struct rdpc_t* rdpc, const char* msg);
fn cb_rdpc_log_msg(rdpc: ?*c.rdpc_t, msg: ?[*:0]const u8) callconv(.C) c_int
{
    if (msg) |amsg|
    {
        if (rdpc) |ardpc|
        {
            const session: ?*rdp_session_t =
                    @alignCast(@ptrCast(ardpc.user));
            if (session) |asession|
            {
                asession.log_msg_slice(std.mem.sliceTo(amsg, 0)) catch
                        return c.LIBRDPC_ERROR_MEMORY;
                return c.LIBRDPC_ERROR_NONE;
            }
        }
    }
    return c.LIBRDPC_ERROR_NONE;
}

//*****************************************************************************
// callback
// int (*send_to_server)(struct rdpc_t* rdpc, void* data, int bytes);
fn cb_rdpc_send_to_server(rdpc: ?*c.rdpc_t,
        data: ?*anyopaque, bytes: u32) callconv(.C) c_int
{
    var rv: c_int = c.LIBRDPC_ERROR_PARSE;
    if (rdpc) |ardpc|
    {
        if (data) |adata|
        {
            const session: ?*rdp_session_t =
                    @alignCast(@ptrCast(ardpc.user));
            if (session) |asession|
            {
                var slice: []u8 = undefined;
                slice.ptr = @ptrCast(adata);
                slice.len = bytes;
                rv = c.LIBRDPC_ERROR_NONE;
                asession.send_slice_to_server(slice) catch
                        return c.LIBRDPC_ERROR_PARSE;
            }
        }
    }
    return rv;
}

//*****************************************************************************
// callback
// int (*set_surface_bits)(struct rdpc_t* rdpc,
//                         struct bitmap_data_t* bitmap_data);
fn cb_rdpc_set_surface_bits(rdpc: ?*c.rdpc_t,
        bitmap_data: ?*c.bitmap_data_t) callconv(.C) c_int
{
    var rv: c_int = c.LIBRDPC_ERROR_PARSE;
    if (rdpc) |ardpc|
    {
        if (bitmap_data) |abitmap_data|
        {
            const session: ?*rdp_session_t =
                    @alignCast(@ptrCast(ardpc.user));
            if (session) |asession|
            {
                rv = c.LIBRDPC_ERROR_NONE;
                asession.set_surface_bits(abitmap_data) catch
                        return c.LIBRDPC_ERROR_PARSE;
            }
        }
    }
    return rv;
}

//*****************************************************************************
// callback
// int (*set_surface_bits)(struct rdpc_t* rdpc,
//                         uint16_t frame_action, uint32_t frame_id);
fn cb_rdpc_frame_marker(rdpc: ?*c.rdpc_t,
        frame_action: u16, frame_id: u32) callconv(.C) c_int
{
    var rv: c_int = c.LIBRDPC_ERROR_PARSE;
    if (rdpc) |ardpc|
    {
        const session: ?*rdp_session_t =
                @alignCast(@ptrCast(ardpc.user));
        if (session) |asession|
        {
            rv = c.LIBRDPC_ERROR_NONE;
            asession.frame_marker(frame_action, frame_id) catch
                    return c.LIBRDPC_ERROR_PARSE;
        }
    }
    return rv;
}

//*****************************************************************************
// callback
// int (*pointer_update)(struct rdpc_t* rdpc,
//                       struct pointer_t* pointer);
fn cb_rdpc_pointer_update(rdpc: ?*c.rdpc_t,
        pointer: ?*c.pointer_t) callconv(.C) c_int
{
    var rv: c_int = c.LIBRDPC_ERROR_PARSE;
    if (rdpc) |ardpc|
    {
        if (pointer) |apointer|
        {
            const session: ?*rdp_session_t =
                    @alignCast(@ptrCast(ardpc.user));
            if (session) |asession|
            {
                rv = c.LIBRDPC_ERROR_NONE;
                asession.pointer_update(apointer) catch
                        return c.LIBRDPC_ERROR_PARSE;
            }
        }
    }
    return rv;
}

//*****************************************************************************
// callback
// int (*pointer_cached)(struct rdpc_t* rdpc,
//                       uint16_t cache_index);
fn cb_rdpc_pointer_cached(rdpc: ?*c.rdpc_t, cache_index: u16) callconv(.C) c_int
{
    var rv: c_int = c.LIBRDPC_ERROR_PARSE;
    if (rdpc) |ardpc|
    {
        const session: ?*rdp_session_t =
                @alignCast(@ptrCast(ardpc.user));
        if (session) |asession|
        {
            rv = c.LIBRDPC_ERROR_NONE;
            asession.pointer_cached(cache_index) catch
                    return c.LIBRDPC_ERROR_PARSE;
        }
    }
    return rv;
}

//*****************************************************************************
// callback
// int (*channel)(struct rdpc_t* rdpc, uint16_t channel_id,
//                void* data, uint32_t bytes);
fn cb_rdpc_channel(rdpc: ?*c.rdpc_t, channel_id: u16,
        data: ?*anyopaque, bytes: u32) callconv(.C) c_int
{
    var rv: c_int = c.LIBRDPC_ERROR_CHANNEL;
    if (rdpc) |ardpc|
    {
        const session: ?*rdp_session_t =
                @alignCast(@ptrCast(ardpc.user));
        if (session) |asession|
        {
            if (c.svc_process_data(asession.svc, channel_id,
                    data, bytes) == c.LIBSVC_ERROR_NONE)
            {
                rv = c.LIBRDPC_ERROR_NONE;
            }
        }
    }
    return rv;
}

//*****************************************************************************
// callback
// int (*log_msg)(struct svc_channels_t* svc, const char* msg);
fn cb_svc_log_msg(svc: ?*c.svc_channels_t,
        msg: ?[*:0]const u8) callconv(.C) c_int
{
    if (msg) |amsg|
    {
        if (svc) |asvc|
        {
            const session: ?*rdp_session_t =
                    @alignCast(@ptrCast(asvc.user));
            if (session) |asession|
            {
                asession.log_msg_slice(std.mem.sliceTo(amsg, 0)) catch
                        return c.LIBSVC_ERROR_MEMORY;
                return c.LIBSVC_ERROR_NONE;
            }
        }
    }
    return c.LIBSVC_ERROR_NONE;
}

//*****************************************************************************
// callback
// int (*send_data)(struct svc_channels_t* svc, uint16_t channel_id,
//                  uint32_t total_bytes, uint32_t flags,
//                  void* data, uint32_t bytes);
fn cb_svc_send_data(svc: ?*c.svc_channels_t, channel_id: u16,
        total_bytes: u32, flags: u32, data: ?*anyopaque,
        bytes: u32) callconv(.C) c_int
{
    if (svc) |asvc|
    {
        const session: ?*rdp_session_t = @alignCast(@ptrCast(asvc.user));
        if (session) |asession|
        {
            asession.logln_devel(log.LogLevel.info, @src(),
                    "total_bytes {} bytes {} flags {}",
                    .{total_bytes, bytes, flags})
                    catch return c.LIBSVC_ERROR_SEND_DATA;
            const rv = c.rdpc_channel_send_data(asession.rdpc, channel_id,
                    total_bytes, flags, data, bytes);
            if (rv == c.LIBRDPC_ERROR_NONE)
            {
                return c.LIBSVC_ERROR_NONE;
            }
        }
    }
    return c.LIBSVC_ERROR_SEND_DATA;
}
