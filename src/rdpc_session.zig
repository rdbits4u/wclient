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

pub const rdp_connect_t = struct
{
    server_name: [512]u8 = std.mem.zeroes([512]u8),
    server_port: [64]u8 = std.mem.zeroes([64]u8),
};

pub const rdp_session_t = struct
{
    allocator: *const std.mem.Allocator,
    rdp_connect: *rdp_connect_t,

    //*************************************************************************
    pub fn create(allocator: *const std.mem.Allocator,
            settings: *c.rdpc_settings_t,
            rdp_connect: *rdp_connect_t) !*rdp_session_t
    {
        _ = settings;
        const self = try allocator.create(rdp_session_t);
        errdefer allocator.destroy(self);
        // init self
        self.* = .{.allocator = allocator, .rdp_connect = rdp_connect};
        return self;
    }

    //*************************************************************************
    pub fn delete(self: *rdp_session_t) void
    {
        self.allocator.destroy(self);
    }

    //*************************************************************************
    pub fn connect(self: *rdp_session_t) !void
    {
        _ = self;
    }

    //*************************************************************************
    pub fn loop(self: *rdp_session_t) !void
    {
        _ = self;
    }

};

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
