const std = @import("std");
const log = @import("log");
const hexdump = @import("hexdump");

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

pub const rdp_session_t = struct
{
    allocator: *const std.mem.Allocator,
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
