const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const emulator = @import("chip_8.zig");
const std = @import("std");
const assert = @import("std").debug.assert;
const process = std.process;

const SDLError = error {
    SDLWindowInitializationFailed,
    SDLRendererInitializationFailed,
    SDLTextureInitializationFailed,
};

var window: ?*c.SDL_Window = null;
var renderer: ?*c.SDL_Renderer = null;
var sdl_texture: ?*c.SDL_Texture = null;
var cpu: *emulator = undefined;


const keymap: [16]c_int = [_]c_int {
    c.SDL_SCANCODE_X,
    c.SDL_SCANCODE_1,
    c.SDL_SCANCODE_2,
    c.SDL_SCANCODE_3,
    c.SDL_SCANCODE_4,
    c.SDL_SCANCODE_Q,
    c.SDL_SCANCODE_W,
    c.SDL_SCANCODE_E,
    c.SDL_SCANCODE_A,
    c.SDL_SCANCODE_S,
    c.SDL_SCANCODE_D,
    c.SDL_SCANCODE_Z,
    c.SDL_SCANCODE_C,
    c.SDL_SCANCODE_R,
    c.SDL_SCANCODE_F,
    c.SDL_SCANCODE_V,
};

pub fn init() !void{     
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    
    std.debug.print("Initializing SDL", .{});

    try create_window();

    try create_renderer();

    try texture();
}

pub fn deinit() void {
    destory_window();
    window = null;

    destroy_renderer();
    renderer = null;

    deinit_texture();
    sdl_texture = null;

    std.debug.print("Quitting SDL\n", .{});
    c.SDL_Quit();
    std.debug.print("Exiting", .{});
}

pub fn create_window() !void {
    window = c.SDL_CreateWindow("Chip-8 Emulator", c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED, 1024, 512, c.SDL_WINDOW_OPENGL);
    if (window == null) {
        c.SDL_Log("Unable to create Window: %s", c.SDL_GetError());
        return SDLError.SDLWindowInitializationFailed;
    }
}

pub fn destory_window() void {
    defer c.SDL_DestroyWindow(window);
}

pub fn create_renderer() !void {
    renderer = c.SDL_CreateRenderer(window, -1, 0);
    if (renderer == null) {
        c.SDL_Log("unable to create renderer");
        return SDLError.SDLRendererInitializationFailed;
    }
}

pub fn destroy_renderer() void {
    defer c.SDL_DestroyRenderer(renderer);
}

pub fn texture() !void {
    sdl_texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA8888, c.SDL_TEXTUREACCESS_STREAMING, 64, 32);
    if (sdl_texture == null) {
        c.SDL_Log("Unable to create texture from surface: %s", c.SDL_GetError());
        return SDLError.SDLTextureInitializationFailed;
    }
}

pub fn deinit_texture() void {
    defer c.SDL_DestroyTexture(sdl_texture);
}

pub fn loadROM(file_name: []const u8, system: *emulator) !void {
    var input_file = try std.fs.cwd().openFile(file_name, .{});
    defer input_file.close();

    std.debug.print("Load ROM\n", .{});

    const size = try input_file.getEndPos();
    std.debug.print("ROMfile size: {}\n", .{size});
    var readr = input_file.reader();

    var i: u16 = 0;
    while (i < size) : (i += 1) {
        system.memory[i + 0x200] = try readr.readByte();
    }

    std.debug.print("Load ROM Success\n", .{});
}

pub fn buildTexture(system: *emulator) void {
    var bytes: ?[*]u32 = null;
    var pitch :c_int= 0;

    const res:[*c]?*anyopaque = @ptrCast(&bytes);
    _ = c.SDL_LockTexture(sdl_texture, null, @as([*c]?*anyopaque, res), &pitch);

    var y: usize = 0;
    while (y < 32) : (y += 1) {
        var x:usize = 0;
        while (x < 64) : (x += 1) {
            bytes.?[y * 64 + x] = if (system.graphics[y * 64 + x] == 1) 0xFFFFFFFF else 0x000000FF;
        }
    }
    c.SDL_UnlockTexture(sdl_texture);
}

pub fn main() !void {
    const slow_factor = 1;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Read command from command line
    var arg_it = try process.argsWithAllocator(allocator);
    _ = arg_it.skip();
    
    const filename = arg_it.next() orelse {
        @panic("No ROM file given!\n");
    };

    // SDL Initialization 
    try init();
    defer deinit();

    var chip_8_cpu = try allocator.create(emulator);
    try chip_8_cpu.init();

    try loadROM(filename, chip_8_cpu);

    var quit = false;
    while (!quit) {
        try chip_8_cpu.cycle();

        var event : c.SDL_Event = undefined;
        while(c.SDL_PollEvent(&event) != 0){
            switch (event.type) {
                c.SDL_QUIT => quit = true,

                c.SDL_KEYDOWN => {
                    if (event.key.keysym.scancode == c.SDL_SCANCODE_ESCAPE) {
                        quit = true;
                    }

                    var i: usize = 0;
                    while(i < 16) : (i += 1) {
                        if (event.key.keysym.scancode == keymap[1]) {
                            chip_8_cpu.keys[i] = 1;
                        }
                    }
                },

                c.SDL_KEYUP => {
                    var i:u8 = 0;
                    while (i < 16) : (i += 1) {
                        if (event.key.keysym.scancode == keymap[i]) {
                            chip_8_cpu.keys[i] = 0;
                        }
                    }
                },

                else => {

                },
            }
        }
        _ = c.SDL_RenderClear(renderer);

        buildTexture(chip_8_cpu);

        var dest = c.SDL_Rect {
            .x = 0,
            .y = 0,
            .w = 1024,
            .h = 512
        };

        _ = c.SDL_RenderCopy(renderer, sdl_texture, null, &dest);
        _ = c.SDL_RenderPresent(renderer);

        std.time.sleep(12 * 1000 * 1000 * slow_factor);
    }
   
}
