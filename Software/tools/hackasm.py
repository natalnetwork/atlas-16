#!/usr/bin/env python3
# =============================================================================
# hackasm.py — Hack+ Assembler für Atlas 16
#
# Erweiterter Hack-Assembler gemäß [N2T] Kapitel 6 mit allen
# Memory-Mapped IO Symbolen des Atlas 16.
#
# Verwendung:
#   python3 hackasm.py programm.asm             # → programm.hack
#   python3 hackasm.py programm.asm -o out.hack # → out.hack
#   python3 hackasm.py programm.asm --bin       # → auch programm.bin
#
# Eingabeformat: Hack+ Assemblersprache (.asm)
#   A-Instruktion:  @wert  oder  @SYMBOL
#   C-Instruktion:  [dest=]comp[;jump]
#   Label:          (LABEL)
#   Kommentar:      // Text bis Zeilenende
#
# Ausgabeformat .hack: ASCII-Binär, eine 16-Bit-Instruktion pro Zeile
#   Beispiel: 0000000000000101
#
# Autor:  Sebastian Schwiebert
# Lizenz: MIT
# =============================================================================

import sys
import os
import argparse

# =============================================================================
# Vordefinierte Symbole (N2T + Atlas 16 Erweiterungen)
# =============================================================================
PREDEFINED = {
    # N2T Standard-Register
    'R0': 0,   'R1': 1,   'R2': 2,   'R3': 3,
    'R4': 4,   'R5': 5,   'R6': 6,   'R7': 7,
    'R8': 8,   'R9': 9,   'R10': 10, 'R11': 11,
    'R12': 12, 'R13': 13, 'R14': 14, 'R15': 15,
    # N2T VM-Zeiger
    'SP': 0, 'LCL': 1, 'ARG': 2, 'THIS': 3, 'THAT': 4,
    # N2T Legacy I/O
    'SCREEN': 0x4000,
    'KBD':    0x6000,
    # ── VGA ──────────────────────────────────────────────────────────────────
    'VGA_MODE':       0x6001,
    'VGA_FB_BASE_LO': 0x6002,
    'VGA_FB_BASE_HI': 0x6003,
    'PALETTE_0':      0x6004,
    'PALETTE_1':      0x6005,
    # ── Sprites (Sprite 0; Sprite n: +n*8) ───────────────────────────────────
    'SPRITE_0_X':      0x6100, 'SPRITE_0_Y':      0x6101,
    'SPRITE_0_ADDR_L': 0x6102, 'SPRITE_0_ADDR_H': 0x6103,
    'SPRITE_0_FLAGS':  0x6104, 'SPRITE_0_CKEY':   0x6105,
    'SPRITE_1_X':      0x6108, 'SPRITE_1_Y':      0x6109,
    'SPRITE_1_ADDR_L': 0x610A, 'SPRITE_1_ADDR_H': 0x610B,
    'SPRITE_1_FLAGS':  0x610C, 'SPRITE_1_CKEY':   0x610D,
    # ── Blitter ──────────────────────────────────────────────────────────────
    'BLIT_SRC_LO':  0x6200, 'BLIT_SRC_HI':  0x6201,
    'BLIT_DST_LO':  0x6202, 'BLIT_DST_HI':  0x6203,
    'BLIT_WIDTH':   0x6204, 'BLIT_HEIGHT':  0x6205,
    'BLIT_COLOR':   0x6206, 'BLIT_COLORKEY':0x6207,
    'BLIT_OP':      0x6208, 'BLIT_START':   0x6209,
    'BLIT_BUSY':    0x620A,
    # ── Sound ────────────────────────────────────────────────────────────────
    'SQ0_FREQ':    0x6300, 'SQ0_VOL':    0x6301,
    'SQ1_FREQ':    0x6302, 'SQ1_VOL':    0x6303,
    'PCM0_ADDR_LO':0x6310, 'PCM0_ADDR_HI':0x6311,
    'PCM0_LEN':    0x6312, 'PCM0_RATE':  0x6313,
    'PCM0_VOL':    0x6314, 'PCM0_CTRL':  0x6315,
    'PCM1_ADDR_LO':0x6316, 'PCM1_ADDR_HI':0x6317,
    'PCM1_LEN':    0x6318, 'PCM1_RATE':  0x6319,
    'PCM1_VOL':    0x631A, 'PCM1_CTRL':  0x631B,
    'MIDI_RX':     0x6330, 'MIDI_STATUS':0x6331,
    # ── UART ─────────────────────────────────────────────────────────────────
    'UART_DATA':   0x6400, 'UART_STATUS': 0x6401,
    # ── RTC ──────────────────────────────────────────────────────────────────
    'RTC_SEC':     0x6410, 'RTC_MIN':    0x6411,
    'RTC_HOUR':    0x6412, 'RTC_DAY':   0x6413,
    'RTC_MON':     0x6414, 'RTC_YEAR':  0x6415,
    # ── Timer ────────────────────────────────────────────────────────────────
    'TMR_CNT':     0x6420, 'TMR_RELOAD': 0x6421,
    'TMR_CTRL':    0x6422, 'TMR_STATUS': 0x6423,
    # ── Bank-Controller ──────────────────────────────────────────────────────
    'BANK_CTRL':   0x6430,
    # ── Eingabegeräte (read-only) ─────────────────────────────────────────────
    'MOUSE_X':     0x6440, 'MOUSE_Y':   0x6441,
    'MOUSE_BTN':   0x6442,
    'PAD_BTN':     0x6460, 'PAD_LEFT':  0x6461,
    'PAD_RIGHT':   0x6462, 'PAD_TRG':   0x6463,
    # ── Gamepad-Button-Masken (als Konstanten) ────────────────────────────────
    'PAD_A':       1,    'PAD_B':       2,
    'PAD_X':       4,    'PAD_Y':       8,
    'PAD_LB':      16,   'PAD_RB':      32,
    'PAD_START':   64,   'PAD_BACK':    128,
    'PAD_DPAD_UP': 256,  'PAD_DPAD_DOWN': 512,
    'PAD_DPAD_LEFT':1024,'PAD_DPAD_RIGHT':2048,
    'PAD_CONNECTED':32768,
}

# =============================================================================
# C-Instruktions-Tabellen (gemäß [N2T] Anhang A)
# =============================================================================
COMP_TABLE = {
    # a=0 (Operand A)
    '0':   '0101010', '1':   '0111111', '-1':  '0111010',
    'D':   '0001100', 'A':   '0110000', '!D':  '0001101',
    '!A':  '0110001', '-D':  '0001111', '-A':  '0110011',
    'D+1': '0011111', 'A+1': '0110111', 'D-1': '0001110',
    'A-1': '0110010', 'D+A': '0000010', 'D-A': '0010011',
    'A-D': '0000111', 'D&A': '0000000', 'D|A': '0010101',
    # a=1 (Operand M)
    'M':   '1110000', '!M':  '1110001', '-M':  '1110011',
    'M+1': '1110111', 'M-1': '1110010', 'D+M': '1000010',
    'D-M': '1010011', 'M-D': '1000111', 'D&M': '1000000',
    'D|M': '1010101',
}

DEST_TABLE = {
    '':    '000', 'M':   '001', 'D':   '010', 'MD':  '011',
    'A':   '100', 'AM':  '101', 'AD':  '110', 'AMD': '111',
}

JUMP_TABLE = {
    '':    '000', 'JGT': '001', 'JEQ': '010', 'JGE': '011',
    'JLT': '100', 'JNE': '101', 'JLE': '110', 'JMP': '111',
}

# =============================================================================
# Hilfsfunktionen
# =============================================================================
def strip_line(line):
    """Kommentare entfernen und Whitespace trimmen."""
    idx = line.find('//')
    if idx >= 0:
        line = line[:idx]
    return line.strip()

def to_bin16(value):
    """Ganzzahl als 16-Bit-Binärstring."""
    if value < 0:
        value = value & 0xFFFF  # Zweierkomplement
    return format(value, '016b')

# =============================================================================
# Erster Durchlauf: Labels sammeln
# =============================================================================
def first_pass(lines):
    """
    Durchläuft alle Zeilen und erstellt eine Tabelle Label→Instruktionsadresse.
    Labels (LABEL) zählen nicht als Instruktionen.
    """
    symbol_table = dict(PREDEFINED)
    instr_count = 0

    for line in lines:
        clean = strip_line(line)
        if not clean:
            continue
        if clean.startswith('(') and clean.endswith(')'):
            label = clean[1:-1]
            if label in symbol_table:
                raise ValueError(f"Label '{label}' bereits definiert.")
            symbol_table[label] = instr_count
        else:
            instr_count += 1

    return symbol_table

# =============================================================================
# Zweiter Durchlauf: Übersetzen
# =============================================================================
def second_pass(lines, symbol_table):
    """
    Übersetzt alle Instruktionen in 16-Bit-Binärcodes.
    Neue Variablen (unbekannte @Symbole) werden ab Adresse 16 vergeben.
    """
    output = []
    next_var_addr = 16  # Variable RAM beginnt nach R0–R15

    for lineno, line in enumerate(lines, 1):
        clean = strip_line(line)
        if not clean or (clean.startswith('(') and clean.endswith(')')):
            continue  # Leerzeile oder Label-Deklaration überspringen

        # ── A-Instruktion (@wert oder @SYMBOL) ──────────────────────────────
        if clean.startswith('@'):
            sym = clean[1:]
            if sym.lstrip('-').isdigit():
                value = int(sym)
                if value < 0 or value > 32767:
                    raise ValueError(f"Zeile {lineno}: Wert {value} außerhalb 0–32767.")
            elif sym in symbol_table:
                value = symbol_table[sym]
            else:
                # Neue Variable: nächste freie RAM-Adresse
                symbol_table[sym] = next_var_addr
                value = next_var_addr
                next_var_addr += 1
            output.append(to_bin16(value))

        # ── C-Instruktion (dest=comp;jump) ───────────────────────────────────
        else:
            # dest=comp;jump parsen
            dest = ''
            comp = clean
            jump = ''

            if '=' in comp:
                dest, comp = comp.split('=', 1)
            if ';' in comp:
                comp, jump = comp.split(';', 1)

            dest = dest.strip()
            comp = comp.strip()
            jump = jump.strip()

            if comp not in COMP_TABLE:
                raise ValueError(
                    f"Zeile {lineno}: Unbekannter comp-Wert '{comp}'.")
            if dest not in DEST_TABLE:
                raise ValueError(
                    f"Zeile {lineno}: Unbekannter dest-Wert '{dest}'.")
            if jump not in JUMP_TABLE:
                raise ValueError(
                    f"Zeile {lineno}: Unbekannter jump-Wert '{jump}'.")

            a_and_c = COMP_TABLE[comp]   # 7 Bits: a + cccccc
            d_bits  = DEST_TABLE[dest]   # 3 Bits
            j_bits  = JUMP_TABLE[jump]   # 3 Bits
            output.append(f'111{a_and_c}{d_bits}{j_bits}')

    return output

# =============================================================================
# Hauptfunktion
# =============================================================================
def assemble(source_path, output_path=None, also_binary=False):
    with open(source_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    symbol_table = first_pass(lines)
    binary_lines  = second_pass(lines, symbol_table)

    # Ausgabepfad bestimmen
    if output_path is None:
        base = os.path.splitext(source_path)[0]
        output_path = base + '.hack'

    # .hack-Datei schreiben (ASCII-Binär)
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(binary_lines) + '\n')

    print(f"[hackasm] {len(binary_lines)} Instruktionen → {output_path}")

    # Optional: rohe Binärdatei
    if also_binary:
        bin_path = os.path.splitext(output_path)[0] + '.bin'
        with open(bin_path, 'wb') as f:
            for word in binary_lines:
                f.write(int(word, 2).to_bytes(2, 'big'))
        print(f"[hackasm] Binärdatei → {bin_path}")

    return binary_lines

# =============================================================================
# Kommandozeilen-Interface
# =============================================================================
if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Hack+ Assembler für Atlas 16',
        epilog='Beispiel: python3 hackasm.py spiel.asm --bin')
    parser.add_argument('source', help='Quelldatei (.asm)')
    parser.add_argument('-o', '--output', help='Ausgabedatei (.hack)')
    parser.add_argument('--bin', action='store_true',
                        help='Zusätzlich Binärdatei (.bin) erzeugen')
    args = parser.parse_args()

    try:
        assemble(args.source, args.output, args.bin)
    except (ValueError, FileNotFoundError) as e:
        print(f"Fehler: {e}", file=sys.stderr)
        sys.exit(1)
