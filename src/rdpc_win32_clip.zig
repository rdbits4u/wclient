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
const rdpc_win32 = @import("rdpc_win32.zig");

pub const cliprdr_format_t = struct
{
    allocator: *const std.mem.Allocator,
    format_id: u32 = 0,
    format_name: []u8 = &.{},

    //*************************************************************************
    fn create(allocator: *const std.mem.Allocator) !*cliprdr_format_t
    {
        const self = try allocator.create(cliprdr_format_t);
        self.* = .{.allocator = allocator};
        return self;
    }

    //*************************************************************************
    fn create_from_format(allocator: *const std.mem.Allocator,
            format: *c.cliprdr_format_t) !*cliprdr_format_t
    {
        const self = try allocator.create(cliprdr_format_t);
        self.* = .{.allocator = allocator,
                .format_id = format.format_id};
        if (format.format_name_bytes > 0)
        {
            if (format.format_name) |aformat_name|
            {
                var lslice: []u8 = undefined;
                lslice.ptr = @ptrCast(aformat_name);
                lslice.len = format.format_name_bytes;
                self.format_name = try self.allocator.alloc(u8, format.format_name_bytes);
                std.mem.copyForwards(u8, self.format_name, lslice);
            }
        }
        return self;
    }

    //*************************************************************************
    fn delete(self: *cliprdr_format_t) void
    {
        self.allocator.free(self.format_name);
        self.allocator.destroy(self);
    }

};

const cliprdr_formats_t = std.ArrayList(*cliprdr_format_t);

pub const rdp_win32_clip_t = struct
{
    allocator: *const std.mem.Allocator,
    session: *rdpc_session.rdp_session_t,
    rdp_win32: *rdpc_win32.rdp_win32_t,
    formats: cliprdr_formats_t,

    channel_id: u16 = 0,

    //*************************************************************************
    pub fn create(allocator: *const std.mem.Allocator,
            session: *rdpc_session.rdp_session_t,
            rdp_win32: *rdpc_win32.rdp_win32_t) !*rdp_win32_clip_t
    {
        const self = try allocator.create(rdp_win32_clip_t);
        const formats = cliprdr_formats_t.init(allocator.*);
        self.* = .{.allocator = allocator, .session = session,
                .rdp_win32 = rdp_win32, .formats = formats};
        return self;
    }

    //*************************************************************************
    pub fn delete(self: *rdp_win32_clip_t) void
    {
        for (self.formats.items) |acliprdr_format|
        {
            acliprdr_format.delete();
        }
        self.formats.deinit();
        self.allocator.destroy(self);
    }

    //*************************************************************************
    pub fn cliprdr_ready(self: *rdp_win32_clip_t, channel_id: u16,
            version: u32, general_flags: u32) !void
    {
        self.channel_id = channel_id;
        _ = version;
        _ = general_flags;
    }

    //*************************************************************************
    pub fn cliprdr_format_list(self: *rdp_win32_clip_t, channel_id: u16,
            msg_flags: u16, num_formats: u32,
            formats: [*]c.cliprdr_format_t) !void
    {
        try self.session.logln(log.LogLevel.debug, @src(),
                "channel_id 0x{X} msg_flags {}", .{channel_id, msg_flags});
        _ = c.cliprdr_send_format_list_response(self.session.cliprdr,
                channel_id, c.CB_RESPONSE_OK);
        // clear formats
        for (self.formats.items) |acliprdr_format|
        {
            acliprdr_format.delete();
        }
        self.formats.clearRetainingCapacity();
        // copy, check formats
        var format_ok = false;
        for (0..num_formats) |index|
        {
            const format = &formats[index];
            try self.session.logln(log.LogLevel.debug, @src(),
                    "index {} format_id {} format_name_bytes {}",
                    .{index, format.format_id, format.format_name_bytes});
            const cliprdr_format = try cliprdr_format_t.create_from_format(
                    self.allocator, format);
            errdefer cliprdr_format.delete();
            const aformat = try self.formats.addOne();
            aformat.* = cliprdr_format;
            if (format.format_id == c.CF_UNICODETEXT)
            {
                format_ok = true;
            }
        }
        if (format_ok)
        {
            //const x11 = self.rdp_x11;
            //_ = c.XSetSelectionOwner(x11.display, x11.clipboard_atom,
            //        x11.window, c.CurrentTime);
        }
    }

    //*************************************************************************
    pub fn cliprdr_format_list_response(self: *rdp_win32_clip_t, channel_id: u16,
            msg_flags: u16) !void
    {
        try self.session.logln(log.LogLevel.debug, @src(),
                "channel_id {} msg_flags {}", .{channel_id, msg_flags});
        //if (self.state != clip_state.send_format_list)
        {
            //try self.session.logln(log.LogLevel.debug, @src(),
            //        "bad state {}, should be send_format_list",
            //        .{self.state});
            //return;
        }
        //self.state = clip_state.idle;
    }

    //*************************************************************************
    pub fn cliprdr_data_request(self: *rdp_win32_clip_t, channel_id: u16,
            requested_format_id: u32) !void
    {
        try self.session.logln(log.LogLevel.debug, @src(),
                "channel_id {} requested_format_id {}",
                .{channel_id, requested_format_id});
        //const win32 = self.rdp_win32;
        if (requested_format_id == c.CF_UNICODETEXT)
        {
            //_ = c.XConvertSelection(x11.display, x11.clipboard_atom,
            //        x11.utf8_atom, x11.clip_property_atom, x11.window,
            //        c.CurrentTime);
        }
    }

    //*************************************************************************
    pub fn cliprdr_data_response(self: *rdp_win32_clip_t, channel_id: u16,
            msg_flags: u16, requested_format_data: ?*anyopaque,
            requested_format_data_bytes: u32) !void
    {
        try self.session.logln(log.LogLevel.debug, @src(),
                "channel_id {} msg_flags {}", .{channel_id, msg_flags});

         _ = requested_format_data;
         _ = requested_format_data_bytes;

        //if (self.state != clip_state.send_requested_data)
        {
            //try self.session.logln(log.LogLevel.debug, @src(),
            //        "bad state {}, should be send_requested_data",
            //        .{self.state});
            //return;
        }
        //self.state = clip_state.idle;
//        if (msg_flags == c.CB_RESPONSE_OK)
//        {
//            if ((self.requested_format == c.CF_UNICODETEXT) and
//                (self.requested_target == self.rdp_x11.utf8_atom))
//            {
//                var utf16_as_u8: []u8 = undefined;
//                utf16_as_u8.ptr = @ptrCast(requested_format_data);
//                utf16_as_u8.len = requested_format_data_bytes;
//                var al = std.ArrayList(u32).init(self.allocator.*);
//                defer al.deinit();
//                try strings.utf16_as_u8_to_u32_array(utf16_as_u8, &al);
//                var utf8 = try self.allocator.alloc(u8, al.items.len * 4 + 1);
//                defer self.allocator.free(utf8);
//                var len: usize = 0;
//                try strings.u32_array_to_utf8Z(&al, utf8, &len);
//                try self.provide_selection(&self.selection_req_event,
//                        self.selection_req_event.target, 8,
//                        &utf8[0], @truncate(len));
//                return;
//            }
//        }
//        try self.refuse_selection(&self.selection_req_event);
    }

};
