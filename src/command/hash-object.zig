const std = @import("std");
const trunk = @import("trunk");

const util = @import("../util.zig");

pub fn execute(
    object_file: []const u8,
    kind: trunk.Object.Kind,
    save: bool,
) !void {
    var f = try std.fs.cwd().openFile(object_file, .{});
    var object: trunk.Object = undefined;

    var arena = std.heap.ArenaAllocator.init(
        std.heap.page_allocator,
    );
    defer arena.deinit();
    const allocator = arena.allocator();

    switch (kind) {
        .blob => {
            object.payload = .{ .blob = .{
                .allocator = allocator,
                .data = try f.readToEndAlloc(
                    allocator,
                    std.math.maxInt(usize),
                ),
            } };
            object.size = object.payload.blob.data.len;
        },
        // TODO
        else => return error.Unimplemented,
    }

    var contents = std.ArrayList(u8).init(allocator);
    _ = try object.write(contents.writer().any());
    const hash_length = std.crypto.hash.Sha1.digest_length;
    var hash: [hash_length]u8 = undefined;
    std.crypto.hash.Sha1.hash(contents.items, &hash, .{});
    const formatter = std.fmt.fmtSliceHexLower(&hash);

    if (save) {
        var repository = try trunk.Repository.find(null);
        defer repository.deinit();

        var hash_string: [hash_length * 2]u8 = undefined;
        var hash_stream = std.io.fixedBufferStream(&hash_string);
        const hs_writer = hash_stream.writer();
        try formatter.format("{}", .{}, hs_writer);

        var dir_buf: [10]u8 =
            .{ 'o', 'b', 'j', 'e', 'c', 't', 's', '/', 0, 0 };
        @memcpy(dir_buf[8..], hash_string[0..2]);

        var contents_stream = std.io.fixedBufferStream(contents.items);
        const contents_reader = contents_stream.reader();

        var dest_dir = try repository.git.makeOpenPath(&dir_buf, .{});
        defer dest_dir.close();
        var dest_file = try dest_dir.createFile(hash_string[2..], .{});
        defer dest_file.close();
        try std.compress.zlib.compress(
            contents_reader,
            dest_file.writer(),
            .{},
        );
    } else {
        const stdout = std.io.getStdOut().writer();
        try formatter.format("{}", .{}, stdout);
        try stdout.print(util.newline, .{});
    }
}
