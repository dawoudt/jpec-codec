const std = @import("std");

pub const std_options: std.Options = .{ .log_level = .info };

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var args_buffer: [2048]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&args_buffer);
    const alloc = fba.threadSafeAllocator();
    const args = try init.minimal.args.toSlice(alloc);

    var path = std.mem.splitBackwardsAny(u8, args[1], "/");
    const file_name = path.first();
    const directory_path = path.rest();

    const directory: std.Io.Dir = try .openDirAbsolute(io, directory_path, .{});
    defer directory.close(io);

    var file = try directory.openFile(io, file_name, .{ .mode = .read_only });
    defer file.close(io);

    var file_buffer: [1024]u8 = undefined;
    var file_reader = file.reader(io, &file_buffer);
    var file_reader_intf = &file_reader.interface;

    var dht_num: usize = 0;
    var dqt_num: usize = 0;
    var sos_num: usize = 0;

    while (true) {
        const byte = try file_reader_intf.takeByte();
        if (byte == MARKER) {
            const next_byte = try file_reader_intf.takeByte();
            std.log.debug("{X}:\n", .{MARKER});
            switch (next_byte) {
                MARKER_CODE_SOI => std.debug.print("SOI[{X}]\n", .{next_byte}),
                MARKER_CODE_EOI => {
                    std.debug.print("EOI[{X}]", .{next_byte});
                    return std.process.cleanExit(io);
                },
                MARKER_FILL => {
                    // std.debug.print("Fill[{X}]", .{next_byte});
                },
                JFIF_APP0 => {
                    var buf: [1024]u8 = undefined;
                    const out = try read_payload(file_reader_intf, &buf);
                    std.debug.print("APP0: {s}\n\n", .{out});
                },
                COM => {
                    var buf: [1024]u8 = undefined;
                    const out = try read_payload(file_reader_intf, &buf);
                    std.debug.print("COM: {s}\n\n", .{out});
                },
                DHT => {
                    dht_num += 1;
                    var buf: [4096]u8 = undefined;
                    const out = try read_payload(file_reader_intf, &buf);
                    std.debug.print("Define Huffman Table {d}: {any}\n\n", .{ dht_num, out });
                },
                DQT => {
                    dqt_num += 1;
                    var buf: [4096]u8 = undefined;
                    const out = try read_payload(file_reader_intf, &buf);
                    std.debug.print("Define Quantization Table {d}: {any}\n\n", .{ dqt_num, out });
                },
                SOS => {
                    sos_num += 1;
                    var buf: [4096]u8 = undefined;
                    const out = try read_payload(file_reader_intf, &buf);
                    std.debug.print("Start of scan {d}: {any}\n\n", .{ sos_num, out });
                },

                else => {
                    std.debug.print("{X:0>2}\n", .{next_byte});
                    continue;
                },
            }
        }
    }
}
fn read_payload(reader: *std.Io.Reader, buf: []u8) ![]u8 {
    const s1: u8 = try reader.takeByte();
    const s2: u8 = try reader.takeByte();
    const len: u16 = std.mem.readInt(u16, &[2]u8{ s1, s2 }, .big);
    const payload_len = len - 2;
    std.log.debug("payload length: {d}", .{payload_len});
    try reader.readSliceAll(buf[0..payload_len]);
    return buf[0..payload_len];
}

const MARKER = 0xFF;
const MARKER_CODE_SOI = 0xD8; // start of image
const MARKER_CODE_EOI = 0xD9; // end of image
const MARKER_FILL = 0x00; // Fill inside entropy-coded scan data
const JFIF_APP0 = 0xE0;
const COM = 0xFE; // Comments
const DHT = 0xC4; // Define Huffman Table
const DQT = 0xDB; // Define Quantization Table
const SOS = 0xDA; // Start of scan
