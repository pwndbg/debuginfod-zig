const std = @import("std");
const helpers = @import("helpers.zig");
const log = @import("log.zig");
const user_agent = @import("user_agent.zig");

pub const ProgressFnType = fn (handle: ?*DebuginfodContext, current: c_long, total: c_long) callconv(.c) c_int;

pub const DebuginfodEnvs = struct {
    // required
    urls: [][]const u8 = &.{},
    cache_path: []const u8 = &.{},
    user_agent: []const u8 = &.{},

    // optional
    fetch_timeout: ?usize = 90,
    fetch_maxsize: ?usize = null,
    fetch_maxtime: ?usize = null,
    fetch_retry_limit: usize = 2,
    fetch_progress_to_stderr: bool = false,
    fetch_headers: ?[]const std.http.Header = null,

    fn init(self: *DebuginfodEnvs, allocator: std.mem.Allocator, io: std.Io, penvs: std.process.EnvMap) !void {
        self.urls = try getUrls(allocator, penvs);
        self.cache_path = try getCachePath(allocator, penvs);
        self.user_agent = try user_agent.getUserAgent(allocator, io);
        self.fetch_headers = try getHeadersFromFile(allocator, io, penvs);

        if (penvs.get("DEBUGINFOD_TIMEOUT")) |val| {
            const d = try std.fmt.parseInt(isize, val, 10);
            self.fetch_timeout = if (d <= 0) null else @intCast(d);
        }
        if (penvs.get("DEBUGINFOD_MAXTIME")) |val| {
            const d = try std.fmt.parseInt(usize, val, 10);
            self.fetch_maxtime = if (d == 0) null else d;
        }
        if (penvs.get("DEBUGINFOD_MAXSIZE")) |val| {
            const d = try std.fmt.parseInt(usize, val, 10);
            self.fetch_maxsize = if (d == 0) null else d;
        }
        if (penvs.get("DEBUGINFOD_RETRY_LIMIT")) |val| {
            self.fetch_retry_limit = try std.fmt.parseInt(usize, val, 10);
        }
        if (penvs.get("DEBUGINFOD_PROGRESS") != null) {
            self.fetch_progress_to_stderr = true;
        }
    }

    pub fn deinit(self: *DebuginfodEnvs, allocator: std.mem.Allocator) void {
        for (self.urls) |url| {
            allocator.free(url);
        }
        allocator.free(self.urls);
        allocator.free(self.cache_path);
        allocator.free(self.user_agent);
        if (self.fetch_headers) |items| {
            for (items) |item| {
                allocator.free(item.name);
                allocator.free(item.value);
            }
            allocator.free(items);
        }
        self.* = undefined;
    }

    fn getHeadersFromFile(allocator: std.mem.Allocator, io: std.Io, penvs: std.process.EnvMap) !?[]const std.http.Header {
        const headers_file = penvs.get("DEBUGINFOD_HEADERS_FILE") orelse {
            return null;
        };
        var file = std.fs.cwd().openFile(headers_file, .{}) catch |err| {
            log.warn("getHeadersFromFile openFile,err: {}", .{err});
            return null;
        };
        defer file.close();

        var buf: [8192]u8 = undefined;
        var reader = file.reader(io, &buf);
        var list = try std.ArrayList(std.http.Header).initCapacity(allocator, 0);

        while (true) {
            const line = reader.interface.takeDelimiter('\n') catch |err| {
                log.warn("getHeadersFromFile takeDelimiter,err: {}", .{err});
                break;
            } orelse {
                break;
            };

            const header_trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (header_trimmed.len == 0) continue;

            const colon_idx = std.mem.indexOf(u8, header_trimmed, ": ") orelse {
                log.warn("getHeadersFromFile invalid header: '{s}'", .{header_trimmed});
                continue;
            };

            const header = std.http.Header{
                .name = try allocator.dupe(u8, header_trimmed[0..colon_idx]),
                .value = try allocator.dupe(u8, header_trimmed[colon_idx + 2 ..]),
            };
            try list.append(allocator, header);
        }
        return try list.toOwnedSlice(allocator);
    }

    // fn getImaCert(allocator: std.mem.Allocator, penvs: std.process.EnvMap) !void {
    //     _ = allocator;
    //     // const env8 = penvs.get("DEBUGINFOD_IMA_CERT_PATH");
    //     // TODO: implement
    // }

    fn getUrls(allocator: std.mem.Allocator, penvs: std.process.EnvMap) ![][]const u8 {
        var list = try std.ArrayList([]const u8).initCapacity(allocator, 0);
        if (penvs.get("DEBUGINFOD_URLS")) |val| {
            // Split by spaces
            var it = std.mem.tokenizeAny(u8, val, " ");
            while (it.next()) |url| {
                if (url.len == 0) continue;

                // allow only http:// and https:// urls
                if (!(std.mem.startsWith(u8, url, "https://") or std.mem.startsWith(u8, url, "http://"))) {
                    continue;
                }

                try list.append(allocator, try allocator.dupe(u8, url));
            }
        }
        return try list.toOwnedSlice(allocator);
    }

    fn getCachePath(allocator: std.mem.Allocator, penvs: std.process.EnvMap) ![]const u8 {
        if (penvs.get("DEBUGINFOD_CACHE_PATH")) |cache_path| {
            return try std.fs.path.join(allocator, &.{cache_path});
        }
        if (penvs.get("XDG_CACHE_HOME")) |cache_path| {
            return try std.fs.path.join(allocator, &.{ cache_path, "debuginfod_client" });
        }
        if (penvs.get("HOME")) |cache_path| {
            return try std.fs.path.join(allocator, &.{ cache_path, ".cache", "debuginfod_client" });
        }

        log.warn("getCachePath erro, envs DEBUGINFOD_CACHE_PATH,XDG_CACHE_HOME,HOME any of them must be not empty", .{});
        return error.EmptyCachePathEnv;
    }
};

test "DebuginfodEnvs" {
    const allocator = std.testing.allocator;
    var threaded: std.Io.Threaded = .init(allocator);
    defer threaded.deinit();
    const io = threaded.io();

    var penvs = try std.process.getEnvMap(allocator);
    defer penvs.deinit();

    try penvs.put("DEBUGINFOD_URLS", "invalidfoo https://test1.com http://test2.com invalidbar");

    var denvs = DebuginfodEnvs{};
    try denvs.init(allocator, io, penvs);
    defer denvs.deinit(allocator);

    try std.testing.expect(denvs.urls.len == 2);
    try std.testing.expectEqualStrings("https://test1.com", denvs.urls[0]);
    try std.testing.expectEqualStrings("http://test2.com", denvs.urls[1]);
}

pub const DebuginfodResponeHeaders = struct {
    size: ?usize = null,
    archive: ?[]const u8 = null,
    file: ?[]const u8 = null,
    imasignature: ?[]const u8 = null,

    allocator: ?std.mem.Allocator = null,
    _buffer: ?[:0]u8 = null,

    fn parseHeaders(it: *std.http.HeaderIterator) !DebuginfodResponeHeaders {
        var out: DebuginfodResponeHeaders = .{};
        while (it.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "x-debuginfod-size")) {
                out.size = try std.fmt.parseInt(usize, header.value, 10);
            } else if (std.ascii.eqlIgnoreCase(header.name, "x-debuginfod-archive")) {
                out.archive = header.value;
            } else if (std.ascii.eqlIgnoreCase(header.name, "x-debuginfod-file")) {
                out.file = header.value;
            } else if (std.ascii.eqlIgnoreCase(header.name, "x-debuginfod-imasignature")) {
                out.imasignature = header.value;
            }
        }
        return out;
    }

    pub fn deinit(self: *DebuginfodResponeHeaders) void {
        const allocator = self.allocator orelse return;
        if (self._buffer) |buf| {
            allocator.free(buf);
        }
        self._buffer = null;
    }

    pub fn toBinding(self: *DebuginfodResponeHeaders) ![:0]u8 {
        const allocator = self.allocator orelse return error.AllocatorIsNotAssigned;
        if (self._buffer) |buf| {
            return buf;
        }

        var list = try std.ArrayList(u8).initCapacity(allocator, 0);
        if (self.size) |val| {
            try list.print(allocator, "x-debuginfod-size: {d}\n", .{val});
        }
        if (self.archive) |val| {
            try list.print(allocator, "x-debuginfod-archive: {s}\n", .{val});
        }
        if (self.file) |val| {
            try list.print(allocator, "x-debuginfod-file: {s}\n", .{val});
        }
        if (self.imasignature) |val| {
            try list.print(allocator, "x-debuginfod-imasignature: {s}\n", .{val});
        }
        if (list.items.len == 0) {
            return error.NoHeaders;
        }
        const output = try list.toOwnedSliceSentinel(allocator, 0);
        self._buffer = output;
        return output;
    }
};

pub const DebuginfodContext = struct {
    allocator: std.mem.Allocator,
    current_request_headers: std.array_list.Aligned(std.http.Header, null),

    envs: DebuginfodEnvs = .{},
    progress_fn: ?*ProgressFnType = null,

    // start variables safe accessable only in `onFetchProgress`
    current_userdata: ?*anyopaque = null,
    current_url: ?[:0]const u8 = null,
    current_response_headers: ?*DebuginfodResponeHeaders = null,
    // end variables safe accessable only in `onFetchProgress`

    pub fn init(allocator: std.mem.Allocator, penvs: std.process.EnvMap) !*DebuginfodContext {
        const ctx = try allocator.create(DebuginfodContext);
        errdefer allocator.destroy(ctx);

        var threaded: std.Io.Threaded = .init(allocator);
        defer threaded.deinit();
        const io = threaded.io();

        ctx.* = .{
            .allocator = allocator,
            .current_request_headers = try std.ArrayList(std.http.Header).initCapacity(allocator, 0),
        };
        try ctx.envs.init(allocator, io, penvs);

        if (ctx.envs.fetch_headers) |headers| {
            for (headers) |header| {
                try ctx.addRequestHeader(header);
            }
        }
        return ctx;
    }

    pub fn deinit(self: *DebuginfodContext) void {
        const allocator = self.allocator;
        self.envs.deinit(allocator);

        for (self.current_request_headers.items) |item| {
            allocator.free(item.name);
            allocator.free(item.value);
        }
        self.current_request_headers.deinit(allocator);

        allocator.destroy(self);
    }

    pub fn addRequestHeader(self: *DebuginfodContext, header: std.http.Header) !void {
        const name = try self.allocator.dupe(u8, header.name);
        errdefer self.allocator.free(name);
        const value = try self.allocator.dupe(u8, header.value);
        errdefer self.allocator.free(value);

        try self.current_request_headers.append(self.allocator, .{
            .name = name,
            .value = value,
        });
    }

    pub fn findDebuginfo(self: *DebuginfodContext, build_id: []const u8) ![]u8 {
        log.info("findDebuginfo {s}", .{build_id});

        const local_path = try std.fs.path.join(self.allocator, &.{ self.envs.cache_path, build_id, "debuginfo" });
        errdefer self.allocator.free(local_path); // caller must free

        if (helpers.fileExists(local_path)) {
            return local_path;
        }

        const url_path = try std.fmt.allocPrint(self.allocator, "/buildid/{s}/debuginfo", .{build_id});
        defer self.allocator.free(url_path);

        try self.fetchFullOptions(url_path, local_path);
        return local_path;
    }

    pub fn findExecutable(self: *DebuginfodContext, build_id: []const u8) ![]u8 {
        log.info("findExecutable {s}", .{build_id});

        const local_path = try std.fs.path.join(self.allocator, &.{ self.envs.cache_path, build_id, "executable" });
        errdefer self.allocator.free(local_path); // caller must free

        if (helpers.fileExists(local_path)) {
            return local_path;
        }

        const url_path = try std.fmt.allocPrint(self.allocator, "/buildid/{s}/executable", .{build_id});
        defer self.allocator.free(url_path);

        try self.fetchFullOptions(url_path, local_path);
        return local_path;
    }

    pub fn findSource(self: *DebuginfodContext, build_id: []const u8, source_path: []const u8) ![]u8 {
        log.info("findSource {s} {s}", .{ build_id, source_path });

        const source_path_encoded = try helpers.urlencodePart(self.allocator, source_path);
        defer self.allocator.free(source_path_encoded);

        const source_path_escaped = try helpers.escapeFilename(self.allocator, source_path);
        defer self.allocator.free(source_path_escaped);

        const cache_part = try std.mem.concat(self.allocator, u8, &.{ "source-", source_path_escaped });
        defer self.allocator.free(cache_part);

        const local_path = try std.fs.path.join(self.allocator, &.{ self.envs.cache_path, build_id, cache_part });
        errdefer self.allocator.free(local_path); // caller must free

        if (helpers.fileExists(local_path)) {
            return local_path;
        }

        const url_path = try std.fmt.allocPrint(self.allocator, "/buildid/{s}/source/{s}", .{ build_id, source_path_encoded });
        defer self.allocator.free(url_path);

        try self.fetchFullOptions(url_path, local_path);
        return local_path;
    }

    pub fn findSection(self: *DebuginfodContext, build_id: []const u8, section: []const u8) ![]u8 {
        log.info("findSection {s} {s}", .{ build_id, section });

        const section_escaped = try helpers.escapeFilename(self.allocator, section);
        defer self.allocator.free(section_escaped);

        const cache_part = try std.mem.concat(self.allocator, u8, &.{ "section-", section_escaped });
        defer self.allocator.free(cache_part);

        const local_path = try std.fs.path.join(self.allocator, &.{ self.envs.cache_path, build_id, cache_part });
        errdefer self.allocator.free(local_path); // caller must free

        if (helpers.fileExists(local_path)) {
            return local_path;
        }

        const url_path = try std.fmt.allocPrint(self.allocator, "/buildid/{s}/section/{s}", .{ build_id, section });
        defer self.allocator.free(url_path);

        try self.fetchFullOptions(url_path, local_path);
        return local_path;
    }

    pub fn findSectionWithFallback(self: *DebuginfodContext, build_id: []const u8, section: []const u8) ![]u8 {
        // TODO: fallback to "findExecutable" + extract from elf, if server don't implement section?
        return try self.findSection(build_id, section);
    }

    fn getTempFilepath(allocator: std.mem.Allocator, local_path: []const u8) ![]u8 {
        const local_dirname = std.fs.path.dirname(local_path) orelse return error.InvalidLocalPath;
        // todo: security? random filename?
        const tmp_basename = try std.mem.concat(allocator, u8, &.{ ".tmp.", std.fs.path.basename(local_path) });
        defer allocator.free(tmp_basename);

        return try std.fs.path.join(allocator, &.{ local_dirname, tmp_basename });
    }

    fn fetchFullOptions(self: *DebuginfodContext, url_path: []const u8, local_path: []const u8) !void {
        var lastErr: anyerror = error.ErrorNotFound;

        for (self.envs.urls) |url| {
            const full_url = try std.mem.concatWithSentinel(self.allocator, u8, &.{ std.mem.cutSuffix(u8, url, "/") orelse url, url_path }, 0);
            defer self.allocator.free(full_url);

            self.fetchAsFile(full_url, local_path) catch |err| {
                lastErr = err;
                continue;
            };
            return;
        }

        return lastErr;
    }

    fn fetchAsFile(self: *DebuginfodContext, url: [:0]const u8, local_path: []const u8) !void {
        self.current_url = url;
        defer self.current_url = null;

        const local_dirname = std.fs.path.dirname(local_path) orelse return error.InvalidLocalPath;
        const local_path_tmp = try getTempFilepath(self.allocator, local_path);
        defer self.allocator.free(local_path_tmp);

        try std.fs.cwd().makePath(local_dirname);

        errdefer std.fs.deleteFileAbsolute(local_path_tmp) catch {};
        {
            var file = try std.fs.createFileAbsolute(local_path_tmp, .{
                .truncate = true,
            });
            defer file.close();

            var buffer: [64 * 1024]u8 = undefined;
            var writer = file.writer(&buffer);

            var threaded: std.Io.Threaded = .init(self.allocator);
            defer threaded.deinit();
            const io = threaded.io();

            var writed_bytes: std.atomic.Value(usize) = .init(0);
            var total_bytes: std.atomic.Value(usize) = .init(0);
            var fetch_finished: std.atomic.Value(bool) = .init(false);

            var ffetch = try io.concurrent(DebuginfodContext.fetch, .{ self, io, url, &writer.interface, &writed_bytes, &total_bytes, &fetch_finished });
            defer ffetch.cancel(io) catch {};

            try self.loopProgress(io, url, &writed_bytes, &total_bytes, &fetch_finished);
            try ffetch.await(io);
        }

        try std.fs.renameAbsolute(local_path_tmp, local_path);
    }

    fn loopProgress(self: *DebuginfodContext, io: std.Io, url: [:0]const u8, writed_bytes: *std.atomic.Value(usize), total_bytes: *std.atomic.Value(usize), fetch_finished: *std.atomic.Value(bool)) anyerror!void {
        const show_progress_stderr = self.progress_fn == null and self.envs.fetch_progress_to_stderr;
        const fetch_start_at = try std.time.Instant.now();

        var progress: std.Progress.Node = undefined;
        var progress_count_one = false;
        if (show_progress_stderr) {
            progress = std.Progress.start(.{
                .root_name = url,
            });
        }
        defer if (show_progress_stderr) progress.end();

        while (!fetch_finished.load(.acquire)) {
            const current_writed_bytes = writed_bytes.load(.acquire);
            const current_total_bytes = total_bytes.load(.acquire);
            const loop_at = try std.time.Instant.now();
            const diff = loop_at.since(fetch_start_at) / std.time.ns_per_s;

            if (self.envs.fetch_timeout != null and current_writed_bytes < 100_000 and diff > self.envs.fetch_timeout.?) {
                return error.DownloadTimeoutExceed;
            }
            if (self.envs.fetch_maxsize != null and self.envs.fetch_maxsize.? < current_writed_bytes) {
                return error.DownloadMaxSizeExceed;
            }
            if (self.envs.fetch_maxtime != null and diff > self.envs.fetch_maxtime.?) {
                return error.DownloadMaxTimeExceed;
            }

            if (show_progress_stderr) {
                if (current_total_bytes > 0 and !progress_count_one) {
                    progress_count_one = true;
                    progress.increaseEstimatedTotalItems(current_total_bytes);
                }
                progress.setCompletedItems(current_writed_bytes);
            } else {
                try self.onFetchProgress(current_writed_bytes, current_total_bytes);
            }

            try io.sleep(.fromMilliseconds(100), .awake);
        }
    }

    fn fetch(self: *DebuginfodContext, io: std.Io, url: [:0]const u8, response_writer: *std.Io.Writer, writed_bytes: *std.atomic.Value(usize), total_bytes: *std.atomic.Value(usize), fetch_finished: *std.atomic.Value(bool)) anyerror!void {
        defer fetch_finished.store(true, .release);
        defer response_writer.flush() catch {};

        log.info("fetch {s}", .{url});

        var client = std.http.Client{
            .allocator = self.allocator,
            .io = io,
        };
        defer client.deinit();

        const redirect_buffer: []u8 = try client.allocator.alloc(u8, 8 * 1024);
        defer client.allocator.free(redirect_buffer);

        var req = try client.request(.GET, try std.Uri.parse(url), .{
            .redirect_behavior = @enumFromInt(3),
            .keep_alive = true,
            .headers = .{
                .user_agent = .{
                    .override = self.envs.user_agent,
                },
            },
            .extra_headers = self.current_request_headers.items,
            .privileged_headers = &.{},
        });
        defer req.deinit();

        try req.sendBodiless();
        var response = try req.receiveHead(redirect_buffer);

        if (response.head.status == .not_found) {
            return error.FetchStatusNotFound;
        }
        if (response.head.status != .ok) {
            return error.FetchStatusNotOk;
        }

        var it = response.head.iterateHeaders();
        var response_headers = try DebuginfodResponeHeaders.parseHeaders(&it);
        response_headers.allocator = self.allocator;
        defer response_headers.deinit();

        self.current_response_headers = &response_headers;
        defer self.current_response_headers = null;

        var file_size: usize = 0;
        if (response_headers.size) |size| {
            file_size = size;
        } else if (response.head.content_encoding == .identity and response.head.content_length != null) {
            file_size = @truncate(response.head.content_length.?);
        }
        total_bytes.store(file_size, .release);

        if (self.envs.fetch_maxsize != null and file_size > 0 and self.envs.fetch_maxsize.? < file_size) {
            return error.DownloadMaxSizeExceed;
        }

        const decompress_buffer: []u8 = switch (response.head.content_encoding) {
            .identity => &.{},
            .zstd => try client.allocator.alloc(u8, std.compress.zstd.default_window_len),
            .deflate, .gzip => try client.allocator.alloc(u8, std.compress.flate.max_window_len),
            .compress => return error.UnsupportedCompressionMethod,
        };
        defer client.allocator.free(decompress_buffer);

        var transfer_buffer: [64]u8 = undefined;
        var decompress: std.http.Decompress = undefined;
        const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);

        while (true) {
            const current_writed_bytes = reader.stream(response_writer, .unlimited) catch |err| switch (err) {
                error.EndOfStream => break,
                else => |e| return e,
            };
            _ = writed_bytes.fetchAdd(current_writed_bytes, .release);
        }
    }

    fn onFetchProgress(self: *DebuginfodContext, current: usize, total: usize) !void {
        if (self.progress_fn) |callback| {
            const download_was_canceled = callback(self, @intCast(current), @intCast(total)) != 0;
            if (download_was_canceled) {
                return error.DownloadInterrupted;
            }
        }
    }
};

pub fn testStartServer(io: std.Io, file_blob: []const u8, queue: *std.Io.Queue(u16)) !void {
    const address = try std.Io.net.IpAddress.parseIp4("127.0.0.1", 0);
    var socket = try address.listen(io, .{});
    errdefer socket.deinit(io);
    try queue.putOne(io, socket.socket.address.getPort());

    defer socket.deinit(io);

    // handle only single conn
    while (true) {
        std.debug.print("wating in loop\n", .{});

        const conn = socket.accept(io) catch |err| {
            std.debug.print("Test HTTP Server accept error: {}\n", .{err});
            break;
        };
        std.debug.print("accepted in loop\n", .{});

        testHandleConnection(io, conn, file_blob) catch |err| switch (err) {
            error.HttpConnectionClosing => break,
            else => |e| return e,
        };
    }

    std.debug.print("exit http loop\n", .{});
}

fn testHandleConnection(io: std.Io, stream: std.Io.net.Stream, file_blob: []const u8) !void {
    defer stream.close(io);

    var req_buf: [2048]u8 = undefined;
    var conn_reader = stream.reader(io, &req_buf);
    var conn_writer = stream.writer(io, &req_buf);

    var http_server = std.http.Server.init(&conn_reader.interface, &conn_writer.interface);
    while (true) {
        std.debug.print("receiveHead start\n", .{});
        var req = http_server.receiveHead() catch |err| {
            std.debug.print("Test HTTP Server error: {}\n", .{err});
            return err;
        };
        std.debug.print("receiveHead end\n", .{});
        testHandleRequest(&req, file_blob) catch |err| {
            std.debug.print("test http error '{s}': {}\n", .{ req.head.target, err });
            req.respond("server error", .{ .status = .internal_server_error }) catch {};
            return err;
        };
    }
}

fn testHandleRequest(req: *std.http.Server.Request, file_blob: []const u8) !void {
    var send_buffer: [4096]u8 = undefined;
    var res = try req.respondStreaming(&send_buffer, .{
        .content_length = file_blob.len,
        .respond_options = .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/octet-stream" },
            },
        },
    });
    try res.writer.writeAll(file_blob);
    try res.writer.flush();
    try res.end();
}

test "DebuginfodContext no exists servers" {
    const allocator = std.testing.allocator;

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var ctx: *DebuginfodContext = undefined;
    {
        var penvs = try std.process.getEnvMap(allocator);
        defer penvs.deinit();
        try penvs.put("DEBUGINFOD_URLS", "invalidfoo https://test1-notexist http://test2-notexist invalidbar");

        const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
        defer allocator.free(tmp_path);
        try penvs.put("DEBUGINFOD_CACHE_PATH", tmp_path);

        ctx = try DebuginfodContext.init(allocator, penvs);
    }
    defer ctx.deinit();

    try std.testing.expectEqual(2, ctx.envs.urls.len);
    try std.testing.expectEqualStrings("https://test1-notexist", ctx.envs.urls[0]);
    try std.testing.expectEqualStrings("http://test2-notexist", ctx.envs.urls[1]);

    _ = ctx.findDebuginfo("ffffff11851246b7766f0a7b3042a8988faad435") catch |err| switch (err) {
        error.NameServerFailure => |e| try std.testing.expectEqual(error.NameServerFailure, e),
        error.UnknownHostName => |e| try std.testing.expectEqual(error.UnknownHostName, e),
        else => |e| try std.testing.expectEqual(error.UnknownHostName, e),
    };
}

test "DebuginfodContext real server" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var threaded: std.Io.Threaded = .init(allocator);
    defer threaded.deinit();
    const io = threaded.io();

    var queue_buf: [1]u16 = undefined;
    var queue: std.Io.Queue(u16) = .init(&queue_buf);

    const contentInFile = "debug content";
    var debug_server = try io.concurrent(testStartServer, .{ io, contentInFile, &queue });
    defer debug_server.cancel(io) catch {};

    const port = try queue.getOne(io);

    var ctx: *DebuginfodContext = undefined;
    {
        var penvs = try std.process.getEnvMap(allocator);
        defer penvs.deinit();

        const DEBUGINFOD_URLS = try std.fmt.allocPrint(allocator, "invalidfoo https://test1-notexist http://test2-notexist http://127.0.0.1:{d} invalidbar", .{port});
        defer allocator.free(DEBUGINFOD_URLS);
        try penvs.put("DEBUGINFOD_URLS", DEBUGINFOD_URLS);

        const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
        defer allocator.free(tmp_path);
        try penvs.put("DEBUGINFOD_CACHE_PATH", tmp_path);

        ctx = try DebuginfodContext.init(allocator, penvs);
    }
    defer ctx.deinit();

    try std.testing.expectEqual(3, ctx.envs.urls.len);

    const filepath = try ctx.findDebuginfo("5c9d8b11851246b7766f0a7b3042a8988faad435");
    defer allocator.free(filepath);

    const debugfile = try std.fs.cwd().openFile(filepath, .{});
    defer debugfile.close();

    var buf: [1024]u8 = undefined;
    const n = try debugfile.read(&buf);

    try std.testing.expectEqualStrings(contentInFile, buf[0..n]);
}
