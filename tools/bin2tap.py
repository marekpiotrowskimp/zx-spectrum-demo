#!/usr/bin/env python3
"""
bin2tap.py - Convert binary Z80 code to ZX Spectrum .TAP format
Supports adding BASIC loader and loading screen
"""

import sys
import struct
from pathlib import Path


def calc_checksum(data: bytes) -> int:
    """Calculate XOR checksum for TAP block"""
    checksum = 0
    for byte in data:
        checksum ^= byte
    return checksum


def create_tap_block(flag: int, data: bytes) -> bytes:
    """Create a TAP block with length, flag, data, and checksum"""
    block_data = bytes([flag]) + data
    checksum = calc_checksum(block_data)
    length = len(block_data) + 1  # +1 for checksum
    return struct.pack('<H', length) + block_data + bytes([checksum])


def create_header(block_type: int, filename: str, data_length: int, 
                  param1: int, param2: int) -> bytes:
    """
    Create 17-byte TAP header
    block_type: 0=Program, 1=NumArray, 2=CharArray, 3=Code
    """
    name = filename[:10].ljust(10).encode('ascii')
    header = bytes([block_type]) + name
    header += struct.pack('<HHH', data_length, param1, param2)
    return create_tap_block(0x00, header)


def create_data_block(data: bytes) -> bytes:
    """Create TAP data block with flag 0xFF"""
    return create_tap_block(0xFF, data)


def basic_number(n: int) -> bytes:
    """ASCII digits followed by the hidden 5-byte integer form."""
    return str(n).encode('ascii') + bytes([0x0E, 0x00, 0x00]) + struct.pack('<H', n) + bytes([0x00])


def create_basic_loader(code_start: int, code_name: str = "zxq") -> bytes:
    """
    BASIC loader:
    10 BORDER 0: PAPER 0: INK 0: CLEAR code_start-1
    20 LOAD "" SCREEN$
    30 POKE 23739,111: LOAD "" CODE
    40 RANDOMIZE USR code_start
    POKE 23739,111 stops the ROM from printing "Bytes: name" over the
    loading screen.
    """
    BORDER, PAPER, INK, CLEAR = 0xE7, 0xDA, 0xD9, 0xFD
    LOAD, SCREEN, CODE, POKE = 0xEF, 0xAA, 0xAF, 0xF4
    RANDOMIZE, USR = 0xF9, 0xC0
    COLON, QUOTE, COMMA, ENTER = 0x3A, 0x22, 0x2C, 0x0D

    lines = [
        (10, bytes([BORDER]) + basic_number(0) + bytes([COLON, PAPER]) + basic_number(0)
         + bytes([COLON, INK]) + basic_number(0) + bytes([COLON, CLEAR])
         + basic_number(code_start - 1) + bytes([ENTER])),
        (20, bytes([LOAD, QUOTE, QUOTE, SCREEN, ENTER])),
        (30, bytes([POKE]) + basic_number(23739) + bytes([COMMA]) + basic_number(111)
         + bytes([COLON, LOAD, QUOTE, QUOTE, CODE, ENTER])),
        (40, bytes([RANDOMIZE, USR]) + basic_number(code_start) + bytes([ENTER])),
    ]
    program = b''
    for line_num, data in lines:
        program += struct.pack('>H', line_num) + struct.pack('<H', len(data)) + data

    header = create_header(0, code_name, len(program), 10, len(program))
    return header + create_data_block(program)


def create_screen_blocks(scr_data: bytes, name: str = "Loading") -> bytes:
    """Create TAP blocks for loading screen (SCREEN$)"""
    if len(scr_data) != 6912:
        raise ValueError(f"Screen data must be 6912 bytes, got {len(scr_data)}")
    
    # Code block starting at 16384 (screen memory)
    header = create_header(3, name, 6912, 16384, 32768)
    data = create_data_block(scr_data)
    
    return header + data


def create_code_blocks(code_data: bytes, start_addr: int, name: str = "Code") -> bytes:
    """Create TAP blocks for machine code"""
    header = create_header(3, name, len(code_data), start_addr, 32768)
    data = create_data_block(code_data)
    
    return header + data


def bin2tap(bin_file: str, tap_file: str, start_addr: int = 32768, 
            name: str = "zxq", scr_file: str = None):
    """
    Convert binary to TAP file with optional loading screen
    """
    # Read binary code
    with open(bin_file, 'rb') as f:
        code_data = f.read()
    
    print(f"Code size: {len(code_data)} bytes")
    print(f"Start address: {start_addr} (0x{start_addr:04X})")
    
    # Build TAP file
    tap_data = b''
    
    # 1. BASIC loader
    tap_data += create_basic_loader(start_addr, name)
    print("Added BASIC loader")
    
    # 2. Loading screen (optional)
    if scr_file and Path(scr_file).exists():
        with open(scr_file, 'rb') as f:
            scr_data = f.read()
        tap_data += create_screen_blocks(scr_data, "Loading")
        print(f"Added loading screen from {scr_file}")
    
    # 3. Machine code
    tap_data += create_code_blocks(code_data, start_addr, name)
    print(f"Added code block: {name}")
    
    # Write TAP file
    with open(tap_file, 'wb') as f:
        f.write(tap_data)
    
    print(f"Created {tap_file} ({len(tap_data)} bytes)")


def main():
    if len(sys.argv) < 3:
        print("Usage: bin2tap.py <input.bin> <output.tap> [start_addr] [name] [screen.scr]")
        print("  start_addr: Start address in decimal (default: 32768)")
        print("  name: Program name (max 10 chars)")
        print("  screen.scr: Optional loading screen (6912 bytes)")
        sys.exit(1)
    
    bin_file = sys.argv[1]
    tap_file = sys.argv[2]
    start_addr = int(sys.argv[3]) if len(sys.argv) > 3 else 32768
    name = sys.argv[4] if len(sys.argv) > 4 else "zxq"
    scr_file = sys.argv[5] if len(sys.argv) > 5 else None
    
    bin2tap(bin_file, tap_file, start_addr, name, scr_file)


if __name__ == '__main__':
    main()
