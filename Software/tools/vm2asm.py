#!/usr/bin/env python3
# =============================================================================
# vm2asm.py — Hack+ VM-Übersetzer für Atlas 16
#
# Übersetzt Hack-VM-Code (N2T Kapitel 7–8) in Hack+ Assembler (.asm).
# Unterstützt alle Standard-N2T-VM-Befehle sowie Atlas 16 I/O-Erweiterungen.
#
# Verwendung:
#   python3 vm2asm.py programm.vm             # → programm.asm
#   python3 vm2asm.py dir/                    # → dir/dir.asm (alle *.vm)
#   python3 vm2asm.py programm.vm -o out.asm  # → out.asm
#   python3 vm2asm.py programm.vm --no-bootstrap  # ohne Sys.init-Aufruf
#
# VM-Befehlsreferenz:
#   Arithmetik/Logik:  add sub neg and or not eq gt lt
#   Stack:             push <segment> <i>   pop <segment> <i>
#   Programmfluss:     label <L>  goto <L>  if-goto <L>
#   Unterprogramme:    function <f> <n>  call <f> <n>  return
#
# Segmente: constant, local, argument, this, that,
#           temp (R5–R12), pointer (THIS/THAT), static
#
# Atlas 16 I/O-Erweiterungen (via call Atlas16.xxx 0):
#   Atlas16.screenMode(mode)    — VGA-Modus setzen
#   Atlas16.screenPoke(x,y,c)   — Pixel setzen (8bpp)
#   Atlas16.screenPrint(row,col,char,color) — Zeichen ausgern
#   Atlas16.readKey()           — Tastatur lesen
#   Atlas16.readMouse()         — Mausposition lesen
#   Atlas16.readPad()           — Gamepad lesen
#   Atlas16.soundTone(ch,freq,vol) — Square-Wave-Ton
#
# Autor:  Sebastian Schwiebert
# Lizenz: MIT
# =============================================================================

import sys
import os
import re
import argparse

# =============================================================================
# Segment-Basisadressen
# =============================================================================
SEGMENT_BASE = {
    'local':    'LCL',
    'argument': 'ARG',
    'this':     'THIS',
    'that':     'THAT',
}

TEMP_BASE  = 5   # R5–R12
POINTER_BASES = {0: 'THIS', 1: 'THAT'}  # pointer 0 = THIS, pointer 1 = THAT

# =============================================================================
# Atlas 16 I/O-Hilfsfunktionen (inline-ASM, werden einmalig ausgegeben)
# =============================================================================
ATLAS16_STDLIB = """\
// ─────────────────────────────────────────────────────────────────────────────
// Atlas16 Standard-Library (inline, generiert von vm2asm.py)
// ─────────────────────────────────────────────────────────────────────────────
// Atlas16.screenMode(mode): VGA_MODE ← ARG[0]
(Atlas16.screenMode)
    @ARG
    A=M
    D=M
    @VGA_MODE
    M=D
    @SP
    AM=M-1
    D=M
    @ARG
    A=M
    M=D
    @LCL
    A=M-1
    D=M
    @R14
    M=D
    @SP
    M=M+1
    @R14
    A=M
    0;JMP

// Atlas16.screenPoke(x, y, c): Pixel bei (x,y) mit Farbe c setzen (8bpp)
// Adresse = VGA_FB_BASE_LO + y*512 + x  (vereinfacht: y*512 = y<<9)
(Atlas16.screenPoke)
    // c = ARG[2], y = ARG[1], x = ARG[0]
    @ARG
    D=M
    @2
    A=D+A
    D=M          // D = c
    @R13
    M=D          // R13 = c
    @ARG
    D=M
    @1
    A=D+A
    D=M          // D = y
    // y * 512: shift left 9 = *256 + *256
    @R14
    M=D
    M=M+M        // *2
    M=M+M        // *4
    M=M+M        // *8
    M=M+M        // *16
    M=M+M        // *32
    M=M+M        // *64
    M=M+M        // *128
    M=M+M        // *256
    M=M+M        // *512
    @ARG
    D=M
    A=D
    D=M          // D = x
    @R14
    M=M+D        // R14 = y*512 + x
    @VGA_FB_BASE_LO
    D=M
    @R14
    M=M+D        // R14 = FB_BASE + y*512 + x
    A=M
    D=A
    @R13
    A=D
    M=M          // Adresse laden…
    // Direkter Pixel-Write: Zieladresse in R14, Farbe in R13
    @R13
    D=M
    @R14
    A=M
    M=D          // *R14 = c
    // return 0
    @0
    D=A
    @SP
    A=M
    M=D
    @SP
    M=M+1
    @Atlas16.screenPoke$ret
    0;JMP
(Atlas16.screenPoke$ret)

// Atlas16.readKey(): D = KBD (0x6000)
(Atlas16.readKey)
    @KBD
    D=M
    @SP
    A=M
    M=D
    @SP
    M=M+1
    @Atlas16.readKey$ret
    0;JMP
(Atlas16.readKey$ret)

// Atlas16.readPad(): D = PAD_BTN (0x6460)
(Atlas16.readPad)
    @PAD_BTN
    D=M
    @SP
    A=M
    M=D
    @SP
    M=M+1
    @Atlas16.readPad$ret
    0;JMP
(Atlas16.readPad$ret)

// Atlas16.soundTone(ch, freq, vol):
//   ch=0: SQ0_FREQ/SQ0_VOL  ch=1: SQ1_FREQ/SQ1_VOL
(Atlas16.soundTone)
    @ARG
    D=M
    A=D
    D=M           // D = ch
    @Atlas16.soundTone$ch1
    D;JNE
    // ch 0
    @ARG
    D=M
    @1
    A=D+A
    D=M
    @SQ0_FREQ
    M=D
    @ARG
    D=M
    @2
    A=D+A
    D=M
    @SQ0_VOL
    M=D
    @Atlas16.soundTone$end
    0;JMP
(Atlas16.soundTone$ch1)
    @ARG
    D=M
    @1
    A=D+A
    D=M
    @SQ1_FREQ
    M=D
    @ARG
    D=M
    @2
    A=D+A
    D=M
    @SQ1_VOL
    M=D
(Atlas16.soundTone$end)
    @0
    D=A
    @SP
    A=M
    M=D
    @SP
    M=M+1
    @Atlas16.soundTone$ret
    0;JMP
(Atlas16.soundTone$ret)
"""

# =============================================================================
# Codewriter — erzeugt Assembler aus VM-Befehlen
# =============================================================================
class CodeWriter:
    def __init__(self, out_path, bootstrap=True):
        self._out   = []
        self._label = 0       # Eindeutiger Zähler für interne Labels
        self._func  = ''      # Aktuelle Funktion (für Label-Namensraum)
        self._file  = ''      # Aktueller VM-Dateiname (für static)
        self._atlas16_needed = set()

        if bootstrap:
            self._write_bootstrap()

    # ─────────────────────────────────────────────────────────────────────────
    # Öffentliche API
    # ─────────────────────────────────────────────────────────────────────────
    def set_file(self, vm_filename):
        """Dateiname ohne Pfad und Extension, z.B. 'Main'."""
        self._file = os.path.splitext(os.path.basename(vm_filename))[0]

    def write_arithmetic(self, cmd):
        self._emit(f'// {cmd}')
        if cmd == 'add':
            self._binary('D+A')
        elif cmd == 'sub':
            self._binary('A-D')
        elif cmd == 'neg':
            self._unary('-D')
        elif cmd == 'not':
            self._unary('!D')
        elif cmd == 'and':
            self._binary('D&A')
        elif cmd == 'or':
            self._binary('D|A')
        elif cmd in ('eq', 'gt', 'lt'):
            self._compare(cmd)
        else:
            raise ValueError(f"Unbekannter arithmetischer Befehl: {cmd}")

    def write_push_pop(self, cmd, segment, index):
        self._emit(f'// {cmd} {segment} {index}')
        if cmd == 'push':
            self._push(segment, index)
        else:
            self._pop(segment, index)

    def write_label(self, label):
        self._emit(f'// label {label}')
        full = f'{self._func}${label}' if self._func else label
        self._emit(f'({full})')

    def write_goto(self, label):
        self._emit(f'// goto {label}')
        full = f'{self._func}${label}' if self._func else label
        self._emit(f'    @{full}')
        self._emit( '    0;JMP')

    def write_if_goto(self, label):
        self._emit(f'// if-goto {label}')
        full = f'{self._func}${label}' if self._func else label
        self._pop_d()
        self._emit(f'    @{full}')
        self._emit( '    D;JNE')

    def write_function(self, name, n_locals):
        self._emit(f'// function {name} {n_locals}')
        self._func = name
        self._emit(f'({name})')
        for _ in range(n_locals):
            # push constant 0
            self._emit('    @0')
            self._emit('    D=A')
            self._push_d()

    def write_call(self, name, n_args):
        self._emit(f'// call {name} {n_args}')
        ret_label = f'{name}$ret.{self._unique()}'
        # push return-address
        self._emit(f'    @{ret_label}')
        self._emit( '    D=A')
        self._push_d()
        # push LCL ARG THIS THAT
        for sym in ('LCL', 'ARG', 'THIS', 'THAT'):
            self._emit(f'    @{sym}')
            self._emit( '    D=M')
            self._push_d()
        # ARG = SP - n_args - 5
        self._emit( '    @SP')
        self._emit( '    D=M')
        self._emit(f'    @{n_args + 5}')
        self._emit( '    D=D-A')
        self._emit( '    @ARG')
        self._emit( '    M=D')
        # LCL = SP
        self._emit( '    @SP')
        self._emit( '    D=M')
        self._emit( '    @LCL')
        self._emit( '    M=D')
        # goto function
        self._emit(f'    @{name}')
        self._emit( '    0;JMP')
        # return address
        self._emit(f'({ret_label})')

    def write_return(self):
        self._emit('// return')
        # FRAME = LCL (in R11)
        self._emit('    @LCL')
        self._emit('    D=M')
        self._emit('    @R11')
        self._emit('    M=D')
        # RET = *(FRAME-5) (in R12)
        self._emit('    @5')
        self._emit('    A=D-A')
        self._emit('    D=M')
        self._emit('    @R12')
        self._emit('    M=D')
        # *ARG = pop()
        self._pop_d()
        self._emit('    @ARG')
        self._emit('    A=M')
        self._emit('    M=D')
        # SP = ARG+1
        self._emit('    @ARG')
        self._emit('    D=M+1')
        self._emit('    @SP')
        self._emit('    M=D')
        # restore THAT THIS ARG LCL (FRAME-1 … FRAME-4)
        for i, sym in enumerate(('THAT', 'THIS', 'ARG', 'LCL'), 1):
            self._emit(f'    @R11')
            self._emit(f'    D=M')
            self._emit(f'    @{i}')
            self._emit(f'    A=D-A')
            self._emit(f'    D=M')
            self._emit(f'    @{sym}')
            self._emit(f'    M=D')
        # goto RET
        self._emit('    @R12')
        self._emit('    A=M')
        self._emit('    0;JMP')

    def close(self, add_atlas16_lib=False):
        """Rückgabe des fertigen Assembler-Codes."""
        lines = list(self._out)
        # Endlos-Schleife am Ende (Programm hält an)
        end = self._unique()
        lines += [
            f'($$END.{end})',
            f'    @$$END.{end}',
            '    0;JMP',
        ]
        if add_atlas16_lib:
            lines += ATLAS16_STDLIB.splitlines()
        return '\n'.join(lines) + '\n'

    # ─────────────────────────────────────────────────────────────────────────
    # Private Hilfsmethoden
    # ─────────────────────────────────────────────────────────────────────────
    def _emit(self, line):
        self._out.append(line)

    def _unique(self):
        self._label += 1
        return self._label

    def _push_d(self):
        """D auf Stack legen."""
        self._emit('    @SP')
        self._emit('    A=M')
        self._emit('    M=D')
        self._emit('    @SP')
        self._emit('    M=M+1')

    def _pop_d(self):
        """Oberstes Stack-Element nach D."""
        self._emit('    @SP')
        self._emit('    AM=M-1')
        self._emit('    D=M')

    def _binary(self, op):
        """Binäre Operation: tos-1 op tos → tos."""
        self._emit('    @SP')
        self._emit('    AM=M-1')
        self._emit('    D=M')        # D = TOS
        self._emit('    A=A-1')
        self._emit(f'    M={op}')    # M[SP-2] = M op D  (A=TOS-1, D=TOS)
        # Achtung: für sub ist op='A-D' (M = M-D, A ist SP-2)
        # Für add: D=TOS, A=SP-2, M=M+D nein → 'D+A' wäre falsch
        # Korrekte Formulierung: M = M (A-1) op D
        # add: D+A → bei A=SP-2: M[SP-2] = M[SP-2] + D ✓
        # sub: A-D → Hack hat kein M-D direkt; nutze D=M, M=D-… nein
        # Für sub müssen wir anders vorgehen:

    def _binary(self, op):
        """Binäre Operation korrekt."""
        self._pop_d()                # D = TOS (y)
        self._emit('    A=A-1')      # A = SP-2 (zeigt auf x)
        if op == 'D+A':              # add: x + y
            self._emit('    M=D+M')
        elif op == 'A-D':            # sub: x - y
            self._emit('    M=M-D')
        elif op == 'D&A':            # and
            self._emit('    M=D&M')
        elif op == 'D|A':            # or
            self._emit('    M=D|M')

    def _unary(self, op):
        """Unäre Operation auf TOS."""
        self._emit('    @SP')
        self._emit('    A=M-1')
        self._emit(f'    M={op}')

    def _compare(self, cmd):
        """Vergleich: eq/gt/lt → -1 (true) oder 0 (false)."""
        uid   = self._unique()
        true  = f'$$TRUE.{uid}'
        end   = f'$$END.{uid}'
        jmp   = {'eq': 'JEQ', 'gt': 'JGT', 'lt': 'JLT'}[cmd]
        self._pop_d()            # D = TOS (y)
        self._emit('    A=A-1')  # A → x
        self._emit('    D=M-D')  # D = x - y
        self._emit(f'    @{true}')
        self._emit(f'    D;{jmp}')
        # false
        self._emit('    @SP')
        self._emit('    A=M-1')
        self._emit('    M=0')
        self._emit(f'    @{end}')
        self._emit('    0;JMP')
        # true
        self._emit(f'({true})')
        self._emit('    @SP')
        self._emit('    A=M-1')
        self._emit('    M=-1')
        self._emit(f'({end})')

    def _push(self, segment, index):
        if segment == 'constant':
            self._emit(f'    @{index}')
            self._emit( '    D=A')
        elif segment in SEGMENT_BASE:
            base = SEGMENT_BASE[segment]
            self._emit(f'    @{index}')
            self._emit( '    D=A')
            self._emit(f'    @{base}')
            self._emit( '    A=M+D')
            self._emit( '    D=M')
        elif segment == 'temp':
            addr = TEMP_BASE + index
            self._emit(f'    @R{addr}')
            self._emit( '    D=M')
        elif segment == 'pointer':
            sym = POINTER_BASES[index]
            self._emit(f'    @{sym}')
            self._emit( '    D=M')
        elif segment == 'static':
            self._emit(f'    @{self._file}.{index}')
            self._emit( '    D=M')
        else:
            raise ValueError(f"Unbekanntes Segment: {segment}")
        self._push_d()

    def _pop(self, segment, index):
        if segment == 'constant':
            raise ValueError("pop constant ist nicht erlaubt.")
        elif segment in SEGMENT_BASE:
            base = SEGMENT_BASE[segment]
            # Zieladresse in R13 speichern
            self._emit(f'    @{index}')
            self._emit( '    D=A')
            self._emit(f'    @{base}')
            self._emit( '    D=M+D')
            self._emit( '    @R13')
            self._emit( '    M=D')
            self._pop_d()
            self._emit( '    @R13')
            self._emit( '    A=M')
            self._emit( '    M=D')
        elif segment == 'temp':
            addr = TEMP_BASE + index
            self._pop_d()
            self._emit(f'    @R{addr}')
            self._emit( '    M=D')
        elif segment == 'pointer':
            sym = POINTER_BASES[index]
            self._pop_d()
            self._emit(f'    @{sym}')
            self._emit( '    M=D')
        elif segment == 'static':
            self._pop_d()
            self._emit(f'    @{self._file}.{index}')
            self._emit( '    M=D')
        else:
            raise ValueError(f"Unbekanntes Segment: {segment}")

    def _write_bootstrap(self):
        self._emit('// Bootstrap: SP = 256, call Sys.init')
        self._emit('    @256')
        self._emit('    D=A')
        self._emit('    @SP')
        self._emit('    M=D')
        self.write_call('Sys.init', 0)


# =============================================================================
# Parser — liest eine .vm-Datei und gibt Befehle zurück
# =============================================================================
ARITH_OPS = {'add', 'sub', 'neg', 'eq', 'gt', 'lt', 'and', 'or', 'not'}

def parse_vm_file(path):
    """Liefert Liste von (befehlstyp, args…)-Tupeln."""
    commands = []
    with open(path, encoding='utf-8') as f:
        for raw in f:
            line = raw.split('//')[0].strip()
            if not line:
                continue
            parts = line.split()
            cmd = parts[0].lower()
            if cmd in ARITH_OPS:
                commands.append(('arithmetic', cmd))
            elif cmd in ('push', 'pop'):
                if len(parts) != 3:
                    raise ValueError(f"Ungültiger {cmd}-Befehl: {line}")
                commands.append((cmd, parts[1], int(parts[2])))
            elif cmd == 'label':
                commands.append(('label', parts[1]))
            elif cmd == 'goto':
                commands.append(('goto', parts[1]))
            elif cmd == 'if-goto':
                commands.append(('if-goto', parts[1]))
            elif cmd == 'function':
                commands.append(('function', parts[1], int(parts[2])))
            elif cmd == 'call':
                commands.append(('call', parts[1], int(parts[2])))
            elif cmd == 'return':
                commands.append(('return',))
            else:
                raise ValueError(f"Unbekannter VM-Befehl: {cmd}")
    return commands


# =============================================================================
# Hauptfunktion
# =============================================================================
def translate(sources, output_path, bootstrap=True):
    """
    sources: Liste von .vm-Dateipfaden.
    output_path: Ausgabe-.asm-Datei.
    """
    # Prüfen ob Atlas16-Lib nötig ist
    needs_atlas16 = False
    for src in sources:
        with open(src, encoding='utf-8') as f:
            if 'Atlas16.' in f.read():
                needs_atlas16 = True
                break

    writer = CodeWriter(output_path, bootstrap=bootstrap)

    for src in sources:
        writer.set_file(src)
        commands = parse_vm_file(src)
        for cmd in commands:
            kind = cmd[0]
            if kind == 'arithmetic':
                writer.write_arithmetic(cmd[1])
            elif kind in ('push', 'pop'):
                writer.write_push_pop(kind, cmd[1], cmd[2])
            elif kind == 'label':
                writer.write_label(cmd[1])
            elif kind == 'goto':
                writer.write_goto(cmd[1])
            elif kind == 'if-goto':
                writer.write_if_goto(cmd[1])
            elif kind == 'function':
                writer.write_function(cmd[1], cmd[2])
            elif kind == 'call':
                writer.write_call(cmd[1], cmd[2])
            elif kind == 'return':
                writer.write_return()

    asm_code = writer.close(add_atlas16_lib=needs_atlas16)

    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(asm_code)

    total = sum(
        1 for line in asm_code.splitlines()
        if line.strip() and not line.strip().startswith('//')
        and not (line.strip().startswith('(') and line.strip().endswith(')'))
    )
    print(f"[vm2asm] {len(sources)} Datei(en) → {output_path}  ({total} ASM-Zeilen)")


# =============================================================================
# Kommandozeilen-Interface
# =============================================================================
def collect_vm_files(path):
    if os.path.isfile(path):
        if not path.endswith('.vm'):
            raise ValueError(f"Erwartet .vm-Datei, erhalten: {path}")
        return [path], os.path.splitext(path)[0] + '.asm'
    elif os.path.isdir(path):
        files = sorted(f for f in os.listdir(path) if f.endswith('.vm'))
        if not files:
            raise ValueError(f"Keine .vm-Dateien in {path}")
        name = os.path.basename(path.rstrip('/\\'))
        return ([os.path.join(path, f) for f in files],
                os.path.join(path, name + '.asm'))
    else:
        raise FileNotFoundError(f"Nicht gefunden: {path}")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='Hack+ VM-Übersetzer für Atlas 16',
        epilog='Beispiel: python3 vm2asm.py spiel.vm   oder   python3 vm2asm.py SpielDir/')
    parser.add_argument('source', help='VM-Datei (.vm) oder Verzeichnis')
    parser.add_argument('-o', '--output', help='Ausgabedatei (.asm)')
    parser.add_argument('--no-bootstrap', action='store_true',
                        help='Bootstrap-Code weglassen (kein Sys.init-Aufruf)')
    args = parser.parse_args()

    try:
        sources, default_out = collect_vm_files(args.source)
        out = args.output or default_out
        translate(sources, out, bootstrap=not args.no_bootstrap)
    except (ValueError, FileNotFoundError) as e:
        print(f"Fehler: {e}", file=sys.stderr)
        sys.exit(1)
