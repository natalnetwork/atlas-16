#!/usr/bin/env python3
"""
hack_load.py — Lädt ein Hack-Programm per UART in den Atlas 16

Protokoll:
  PC → FPGA:  2 Byte Wortanzahl (Big-Endian) + N×2 Byte Instruktionen
  FPGA → PC:  0xAA = OK, 0xFF = Fehler

Verwendung:
  python3 hack_load.py /dev/ttyUSB0 programm.hack
  python3 hack_load.py /dev/ttyUSB0 --test-loop    # sendet Endlosschleife

Format .hack: eine Instruktion pro Zeile, 16-bit binär (N2T-Assembler-Ausgabe)
  z.B.  0000000000000000
        1110101010000111
"""

import sys
import serial
import time
import argparse

BAUD = 115_200
TIMEOUT = 5.0   # Sekunden auf ACK warten


def load_hack_file(path: str) -> list[int]:
    """Liest .hack-Datei, gibt Liste von 16-bit Instruktionen zurück."""
    instructions = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("//"):
                continue
            instructions.append(int(line, 2))
    return instructions


def test_loop_program() -> list[int]:
    """Minimales Programm: springt endlos zu sich selbst. Weißer Bildschirm."""
    # @0       → 0x0000
    # 0;JMP    → 0xEA07
    return [0x0000, 0xEA07]


def white_screen_program() -> list[int]:
    """Füllt den Framebuffer (0x4000–0x5FFF) mit 0xFFFF → weißes Bild."""
    # In Hack-Assembly:
    #   @16384    D=A        @R0  M=D    (addr = 16384)
    #   @8192     D=A        @R1  M=D    (count = 8192)
    #   (LOOP)
    #   @R0  A=M  M=-1               (mem[addr] = 0xFFFF)
    #   @R0  M=M+1                   (addr++)
    #   @R1  MD=M-1                  (count--)
    #   @LOOP  D;JGT
    #   (END) @END 0;JMP
    return [
        0x4000, 0xFC10, 0x0000, 0xE310,   # @16384 D=A @R0 M=D
        0x2000, 0xFC10, 0x0001, 0xE310,   # @8192  D=A @R1 M=D
        0x0000, 0xFC87,                    # @R0 A=M M=-1
        0x0000, 0xFD08,                    # @R0 M=M+1
        0x0001, 0xF819,                    # @R1 MD=M-1
        0x0008, 0xE301,                    # @LOOP D;JGT   (@8 = LOOP-Adresse)
        0x000E, 0xEA87,                    # (END) @END 0;JMP
    ]


def send_program(port: str, instructions: list[int]) -> bool:
    count = len(instructions)
    if count == 0 or count > 32767:
        print(f"Fehler: ungültige Wortanzahl {count}")
        return False

    payload = bytearray()
    payload.append((count >> 8) & 0x7F)   # HIGH-Byte (max 7 Bit)
    payload.append(count & 0xFF)           # LOW-Byte
    for instr in instructions:
        payload.append((instr >> 8) & 0xFF)
        payload.append(instr & 0xFF)

    print(f"Sende {count} Instruktionen ({len(payload)} Bytes) → {port}")

    with serial.Serial(port, BAUD, timeout=TIMEOUT) as ser:
        ser.write(payload)
        ser.flush()

        print("Warte auf ACK...", end=" ", flush=True)
        ack = ser.read(1)
        if not ack:
            print("TIMEOUT — kein ACK empfangen")
            return False
        if ack[0] == 0xAA:
            print("0xAA ✓  CPU läuft")
            return True
        elif ack[0] == 0xFF:
            print("0xFF ✗  FPGA meldet Fehler (Wortanzahl ungültig)")
            return False
        else:
            print(f"Unbekanntes ACK: 0x{ack[0]:02X}")
            return False


def main():
    parser = argparse.ArgumentParser(description="Atlas 16 UART-Loader")
    parser.add_argument("port", help="Serieller Port, z.B. /dev/ttyUSB0")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("file", nargs="?", help=".hack-Datei (N2T-Binärformat)")
    group.add_argument("--test-loop",   action="store_true", help="Endlosschleife (2 Instruktionen)")
    group.add_argument("--test-white",  action="store_true", help="Weißer Bildschirm")
    args = parser.parse_args()

    if args.test_loop:
        instructions = test_loop_program()
        print("Testprogramm: Endlosschleife")
    elif args.test_white:
        instructions = white_screen_program()
        print("Testprogramm: Weißer Bildschirm")
    else:
        instructions = load_hack_file(args.file)
        print(f"Programm: {args.file} ({len(instructions)} Worte)")

    success = send_program(args.port, instructions)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
