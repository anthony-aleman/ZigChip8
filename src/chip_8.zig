const std = @import("std");
const c_std = @cImport(
    @cInclude("stdlib.h")
);
const c_time = @cImport(
    @cInclude("time.h")
);

// Store the Current operation code
current_opcode: u16,

//Chip-8 Memory  4Kb (4,096 bytes)
//
// |===============| <- 0xFFF (4096) end of chip 8 RAM
// |               |
// |    Chip-8     |        0x200 -> 0xFFF
// | Program/Data  |    { Program ROM and Working RAM }
// |     Space     |
// |               |
// |===============| <- 0x200 (512) Start of (most) Chip 8 programs
// |  Reserved for | <- 0x1FF (511) End of memory for Interpreter
// |  interpreter  |        0x050 -> 0x0A0
// |               |    { Space set aside for the Pixel font set }
// |===============|<- 0x000 (0) Start of the chip 8 RAM
//
memory: [4096]u8,

// Chip 8 Display Graphics 
// Black & White Pixels on 64 x 32 screen each pixel representing a bit
//
// |===============================|
// | (0,0)                  (63,0) |
// |                               |
// |                               |
// |                               |
// | (0, 31)              (63, 31) |
// |===============================|

graphics: [64 * 32]u8,

// 16 general 8 bit Registers V0,V1...VE
registers: [16]u8, // VF Register is used as a flag 

// Memory address register
// Index Register - 16 bit register that points at locations in memory 
// Program counter - 16 bit register points at the current executing instruction's memory address
index: u16,
program_counter: u16, 

// Timer registers
// Delay Timer - 8 bit register that decrements at a rate of 60/second until it equals 0
// Sound Timer - 8 bit register that also acts like the delay timer as long as it's value > 0 
//            | the buzzer will sound when value == 0 then sound will deactivate
delay_timer: u8,
sound_timer: u8,

//Stack
stack: [32]u16,
stack_pointer: u16,


//Keys - 16 key keypad 
// |===|===|===|===|
// | 1 | 2 | 3 | C |
// |===|===|===|===|
// | 4 | 5 | 6 | D |
// |===|===|===|===|
// | 7 | 8 | 9 | E |
// |===|===|===|===|
// | A | 0 | B | F |
// |===|===|===|===|
//
keys: [16]u8,


// 4 X 5 Pixel font 
const chip8_fontset = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

const Self = @This();
pub fn init(self: *Self) !void {
    const time: u32 = @intCast(c_time.time(0));

    c_std.srand(@as(u32, time));
    self.clear_environment();
}


pub fn clear_environment(self: *Self) void {
    //start of the program
    self.program_counter = 0x200;

    self.current_opcode = 0x00;

    self.index = 0x00;

    self.stack_pointer = 0x00;

    // Clear the display
    self.cls();

    //clear stack
    for (&self.stack) |*s| {
        s.* = 0x00;
    }

    //Clear All general registers
    for (&self.registers) |*bit| {
        bit.* = 0x00;
    }

    //clear memory
    for (&self.memory) |*mem| {
        mem.* = 0x00;
    }

    //clear keys
    for (&self.keys) |*key| {
        key.* = 0x00;
    }

    for (chip8_fontset, 0..) |character, idx| {
        self.memory[idx] = character;
    }

    self.delay_timer = 0;
    self.sound_timer = 0;
}

pub fn cls(self: *Self) void {
    for (&self.graphics) |*bit| {
        bit.* = 0;
    }
    self.increment_program_counter();
}

pub fn increment_program_counter(self: *Self) void {
    self.program_counter += 2;
}


pub fn cycle(self: *Self) !void {
    // If the program counter is at EOF return error
    if (self.program_counter > 0xFFF) {
        @panic("Operation code is out of range of memory");
    }

    const tmp: u16= @intCast(self.memory[self.program_counter]);

    self.current_opcode = @as(u16, tmp) << 8 | self.memory[self.program_counter + 1];
    // Chip 8 instructions

    //Clear the display
    // 00E0 - CLS
    if (self.current_opcode == 0x00E0) {
        self.cls();
    } 
    // 00EE - RET
    else if (self.current_opcode == 0x00EE) {
        // Return from a subroutine
        self.stack_pointer -= 1;
        // Set current instructuon to 
        self.program_counter = self.stack[self.stack_pointer];
        self.increment_program_counter();
    } else {
        const first = self.current_opcode >> 12;

        switch (first)  {
            // Unimplemented sys instruction
            0x0 => {
                std.debug.print("Unimplemented SYS Instruction", .{});
                self.increment_program_counter();
            },
            // 1nnn - JPP addr
            0x1 => { // Jump to NNN (memory address)
                self.program_counter = self.current_opcode & 0x0FFF;
            },

            // 2nnn - CALL addr
            0x2 => { // Call subroutine at nnn 
                // Current instruction is pushed to the stack
                self.stack[self.stack_pointer] = self.program_counter;
                // Stack pointer is incremented
                self.stack_pointer += 1;
                // Bitwise AND operation
                self.program_counter = self.current_opcode & 0x0FFF;
            },

            // 3xkk - SE Vx, byte
            0x3 => {
                // Skip next instruction if Register Vx == kk
                const kk: u16 = self.current_opcode & 0x00FF;
                const trunc_kk: u8 = @truncate(kk);
                const x = (self.current_opcode & 0x0F00) >> 8;
                if (self.registers[x] == @as(u8, trunc_kk)) {
                    self.increment_program_counter();
                }
                self.increment_program_counter();
            },

            //4xkk - SNE Vx, byte
            0x4 => {
                // SKip next instruction if Vx != kk
                const kk = self.current_opcode & 0x00FF;
                const trunc_kk: u8 = @truncate(kk);
                const x = (self.current_opcode & 0x0F00) >> 8;

                if (self.registers[x] != @as(u8, trunc_kk)) {
                    self.increment_program_counter();
                }
                self.increment_program_counter();
            },

            // 5xy0 - SE Vx, Vy
            0x5 => {
                const x = (self.current_opcode & 0x0F00) >> 8;
                const y = (self.current_opcode & 0x00F0) >> 4;
                //Skip the next instruction if register Vx == register Vy
                if (self.registers[x] == self.registers[y]) {
                    self.increment_program_counter();
                }
                self.increment_program_counter();

            },

            // 6xkk LD Vx, byte
            0x6 => {
                const kk: u16 = self.current_opcode & 0x00FF;
                const trunc_kk: u8 = @truncate(kk);
                const x = (self.current_opcode & 0x0F00) >> 8;
                // Set register Vx to kk
                self.registers[x] = @as(u8, trunc_kk);
                self.increment_program_counter();
            },

            //7xkk ADD Vx, byte
            0x7 => {
                @setRuntimeSafety(false);
                // Set register Vx to (Vx + kk)
                const kk: u16 = self.current_opcode & 0x00FF;
                const trunc_kk: u8 = @truncate(kk);
                const x = (self.current_opcode & 0x0F00) >> 8;
                self.registers[x] += @as(u8, trunc_kk);
                self.increment_program_counter();
            },

            0x8 => {
                const x = (self.current_opcode & 0x0F00) >> 8;
                const y = (self.current_opcode & 0x00F0) >> 4;
                const m = (self.current_opcode & 0x000F);

                switch (m) {
                    //8xy0 - Ld Vx, Vy
                    0 => {
                        //Load the value of register Vy into the register Vx
                        self.registers[x] = self.registers[y];
                    },

                    //8xy1 - Or Vx, Vy
                    1=> {
                        // Bitwise OR on values in registers Vx, Vy 
                        // and stores result inside of register Vx
                        self.registers[x] |= self.registers[y];
                    },

                    //8xy2 - AND Vx, Vy
                    2 => {
                        // Bitwise AND on the values in registers Vx,Vy
                        // and stores result in vX
                        self.registers[x] &= self.registers[y]; 
                    },

                    //8xy3 - XOr Vx,Vy
                    3 => {
                        // Bitwise Exclusive OR on the values in registers Vx, Vy
                        // Stores the results in Vx
                        self.registers[x] ^= self.registers[y];
                    },

                     //8xy4 - ADD vx, Vy
                    4 => {
                        @setRuntimeSafety(false);
                        // Set register Vx to (Vx + Vy)
                        // Set the VF to 1 if result is bigger thsn 8 bits, only 8 bits are kept and stores in Vx
                        var sum: u16 = self.registers[x];
                        sum += self.registers[y];
                        //const sum: u16 = (self.registers[x] + self.registers[y]);
                        self.registers[0xF] = if (sum > 255) 1 else 0;
                        const res: u8 = @truncate((sum & 0x00FF));
                        self.registers[x] = @as(u8, res);
                    },
                     // 8xy5 - SUB vx, Vy
                    5 => {
                        @setRuntimeSafety(false);
                        // Set register Vx to (Vx - Vy) set VF to 1 if Vx > Vy else 0
                        self.registers[0xF] = if (self.registers[x] > self.registers[y]) 1 else 0;
                        self.registers[x] -= self.registers[y];
                    },
                     // 8xy6 - SHR Vx {, Vy}
                    6 => {
                        // if least significant bit of register Vx is 1 then VF is set to 1  else 0
                        self.registers[0xF] = if ((self.registers[x] & 0b00000001) != 0) 1 else 0;
                        // Then register Vx is divided by 2
                        self.registers[x] >>= 1;
                    },
                     // 8xy7 - SHL Vx {, VY}
                    7 => {
                        @setRuntimeSafety(false);
                        // if register Vx is less than Vy then VF is set to 1 else 0
                        self.registers[0xF]=if (self.registers[y] > self.registers[x]) 1 else 0;
                        self.registers[x] = self.registers[y] - self.registers[x];
                    },
                     // 8xyE - SHL Vx {,Vy}
                    0xE => {
                        // if least significant bit of register Vx is 1 then VF is set to 1  else 0
                        self.registers[0xF] = if(self.registers[x] & 0b10000000 != 0)1 else 0;
                        // Then register Vx is multiplied by 2
                        self.registers[x] <<= 1;

                    },
                    else =>{
                        std.debug.print("Current ALU OP: {x}\n", .{self.current_opcode});
                    },
                }

                self.increment_program_counter();

            },

            // 9xy0 - SNE Vx, Vy
            0x9 =>{
                const x = (self.current_opcode & 0x0F00) >> 8;
                const y = (self.current_opcode & 0x00F0) >> 4;

                //if the values in registers Vx is not equal to Vy
                if (self.registers[x] != self.registers[y]) {
                    //Skip next instruction
                    self.increment_program_counter();
                }
                self.increment_program_counter();
            },

            // Annn - LD I, addr
            0xA =>{
                // Set index register to memory address nnn
                self.index = self.current_opcode & 0x0FFF;
                self.increment_program_counter();
            },


            // Bnnn - JP V0, addr
            0xB => {
                // Jump to a location to address nnn + V0
                
                const addr = (self.current_opcode & 0x0FFF) + @as(u16, self.registers[0]);
                // set program count to nnn + V0
                self.program_counter = addr;
            },

            //Cxkk - RND Vx, byte
            0xC => {
                const x = (self.current_opcode & 0x0F00) >> 8;
                const kk: u16 = self.current_opcode & 0x00FF;
                //const trunc_kk: u8 = @truncate(kk);
                // Generate rand num 
                const rand_num: u32 = @intCast(c_std.rand());

                const res: u32 = rand_num & kk; 

                const bitCast_res: u8 = @truncate(@as(u32,res));
                
                self.registers[x] = @as(u8, bitCast_res);
                self.increment_program_counter();
            },

            //Dxyn - DRW Vx, Vy, nibble
            0xD => {

                self.registers[0xF] = 0;

                const Vx = self.registers[(self.current_opcode & 0x0F00) >> 8];
                const Vy = self.registers[(self.current_opcode & 0x00F0) >> 4];
                const height = self.current_opcode & 0x000F;

                var y:usize = 0;

                while (y < height) : (y += 1) {
                    const spr = self.memory[self.index + y];
                    var x: usize = 0;
                    while (x < 8) : (x += 1) {
                        const msb:u8 = 0x80;
                        const temp: u3 = @intCast(x);
                        if ((spr & (msb >> @as(u3, temp)) != 0) ){
                            const tX = (Vx + x) % 64;
                            const tY = (Vy + y) % 32;

                            const idx = tX + tY * 64;

                            self.graphics[idx] ^= 1;
                            // if pixel is changed VF set to 1
                            if (self.graphics[idx] == 0) {
                                self.registers[0xF] = 1;
                            }
                        }
                    }

                }

                self.increment_program_counter();
            },
            
            
            0xE => {
                const x = (self.current_opcode & 0x0F00) >> 8;
                const m = (self.current_opcode & 0x00FF);
                // Ex9E - SKP Vx
                if (m == 0x9E) {
                // Skip next instruction if key with the value of Vx is pressed
                    if (self.keys[self.registers[x]] == 1) {
                        self.increment_program_counter();
                    }
                } 
                // ExA1 - SKNP Vx
                else if (m == 0xA1) {
                // Skip next instruction of key if the value in register Vx is not pressed
                    if (self.keys[self.registers[x]] != 1) {
                        self.increment_program_counter();
                    }
                } 
                self.increment_program_counter();
            },

            0xF => {
                const x = (self.current_opcode & 0x0F00) >> 8;
                const m = self.current_opcode & 0x00FF;

                // Fx07 - LD Vx, DT
                if (m == 0x07) {
                    // The value of DT is assigned to the register Vx
                    self.registers[x] = self.delay_timer;
                } 
                // Fx0A - LD Vx, K
                else if (m == 0x0A) {
                    var key_press = false;
                    var i:u8 = 0;

                    while (i < 16) : (i += 1){
                        if (self.keys[i] != 0) {
                            self.registers[x] = @as(u8, i);
                            key_press = true;
                        }
                    }

                    if (!key_press) { return; }

                } 
                // Fx15 - LD DT, Vx
                else if (m == 0x15) {
                    // Set Delay timer to value inside register Vx
                    self.delay_timer = self.registers[x];
                } 
                // Fx18 - LD ST, Vx
                else if (m == 0x18) {
                    // Set sound timer to value indise register Vx
                    self.sound_timer = self.registers[x];
                } 
                // Fx1E - ADD I, Vx
                else if (m == 0x1E) {
                    // if value of registers I (index) + Vx is greater than End of Memory  set VF
                    self.registers[0xF] = if (self.index + self.registers[x] > 0xFFF) 1 else 0;
                    self.index += self.registers[x];
                } 
                // Fx29 - LD F, Vx
                else if (m == 0x29) {
                    // set I (index) to location of sprite for digit in register in Vx
                    self.index = self.registers[x] * 0x5;
                } 
                // Fx33 - LD B, Vx
                else if (m == 0x33) {
                    self.memory[self.index] = self.registers[x] / 100;
                    self.memory[self.index + 1] = (self.registers[x] / 10) % 10;
                    self.memory[self.index + 2] = self.registers[x] % 10;
                } 
                // Fx55 - LD [I], Vx
                else if (m == 0x55) {
                    var i: u16 = 0;
                    while (i <= x) : (i += 1) {
                        self.memory[self.index + 1] = self.registers[i];
                    }
                } 
                // Fx65 - LD Vx. [I]
                else if (m == 0x65) {
                    var i: u16 = 0;
                    while (i <= x) : (i += 1) {
                        self.registers[i] = self.memory[self.index + 1];
                    }
                }
                
                self.increment_program_counter();
            },

            else => {
                std.debug.print("Current OP: {x}\n", .{self.current_opcode});
            },
        }
    }

    if (self.delay_timer > 0) {
        self.delay_timer -= 1;
    }

    if (self.sound_timer > 0) {
        //TODO: Sound!
        self.sound_timer -= 1;
    }


}
