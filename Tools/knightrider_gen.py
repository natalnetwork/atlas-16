#!/usr/bin/env python3
"""
Hack-Assembler + Knight-Rider-Programm für Atlas 16.
Ausgabe: knightrider.hack (Big-Endian 16-bit Binär)

Effekt: Ein schwarzer Dot (1 Wort = 16 Pixel breit) bewegt sich
auf weißem Hintergrund in Zeile 128 hin und her.
Bildschirm: 512x256 Pixel, 32 Wörter/Zeile, Weiß=0xFFFF, Schwarz=0x0000
DOT_BASE = 16384 + 128*32 = 20480
"""
import struct, os

ASM = """
// Bildschirm mit Weiß füllen (0xFFFF = -1)
@16384
D=A
@R0
M=D
@8192
D=A
@R1
M=D
(FILL)
@R0
A=M
M=-1
@R0
M=M+1
@R1
MD=M-1
@FILL
D;JGT

// pos=0, dir=1
@0
D=A
@R2
M=D
@1
D=A
@R3
M=D

// Hauptschleife
(LOOP)
@20480
D=A
@R2
D=D+M
@R4
M=D
@R4
A=M
M=0

// Verzögerung (~39ms bei 50MHz: 15 * 32767 * 4 Takte)
@15
D=A
@R6
M=D
(OUTER)
@32767
D=A
@R7
M=D
(INNER)
@R7
MD=M-1
@INNER
D;JGT
@R6
MD=M-1
@OUTER
D;JGT

// Dot löschen
@R4
A=M
M=-1

// pos += dir
@R3
D=M
@R2
M=M+D

// pos >= 32 → zurück
@R2
D=M
@32
D=D-A
@BWD
D;JGE

// pos < 0 → vorwärts
@R2
D=M
@FWD
D;JLT

@LOOP
0;JMP

(BWD)
@30
D=A
@R2
M=D
@R3
M=-1
@LOOP
0;JMP

(FWD)
@1
D=A
@R2
M=D
@R3
M=D
@LOOP
0;JMP
"""

COMP = {
    '0':(0,0b101010),'1':(0,0b111111),'-1':(0,0b111010),
    'D':(0,0b001100),'A':(0,0b110000),'!D':(0,0b001101),
    '!A':(0,0b110001),'-D':(0,0b001111),'-A':(0,0b110011),
    'D+1':(0,0b011111),'A+1':(0,0b110111),'D-1':(0,0b001110),
    'A-1':(0,0b110010),'D+A':(0,0b000010),'A+D':(0,0b000010),
    'D-A':(0,0b010011),'A-D':(0,0b000111),'D&A':(0,0b000000),
    'D|A':(0,0b010101),
    'M':(1,0b110000),'!M':(1,0b110001),'-M':(1,0b110011),
    'M+1':(1,0b110111),'M-1':(1,0b110010),'D+M':(1,0b000010),
    'M+D':(1,0b000010),'D-M':(1,0b010011),'M-D':(1,0b000111),
    'D&M':(1,0b000000),'D|M':(1,0b010101),
}
DEST = {'':0,'M':1,'D':2,'MD':3,'A':4,'AM':5,'AD':6,'AMD':7}
JUMP = {'':0,'JGT':1,'JEQ':2,'JGE':3,'JLT':4,'JNE':5,'JLE':6,'JMP':7}
PREDEF = {**{f'R{i}':i for i in range(16)},
          'SCREEN':16384,'KBD':24576,'SP':0,'LCL':1,'ARG':2,'THIS':3,'THAT':4}

def parse_c(line):
    dest, comp, jump = '', line, ''
    if ';' in comp:
        comp, jump = comp.split(';',1)
    if '=' in comp:
        dest, comp = comp.split('=',1)
    a,c = COMP[comp.strip()]
    d = DEST[dest.strip()]
    j = JUMP[jump.strip()]
    return 0b111<<13 | a<<12 | c<<6 | d<<3 | j

def assemble(src):
    syms = dict(PREDEF)
    lines = []
    for raw in src.splitlines():
        line = raw.split('//')[0].strip()
        if not line:
            continue
        if line.startswith('(') and line.endswith(')'):
            syms[line[1:-1]] = len(lines)
        else:
            lines.append(line)
    var_next = 16
    out = []
    for line in lines:
        if line.startswith('@'):
            sym = line[1:]
            if sym.isdigit():
                val = int(sym)
            else:
                if sym not in syms:
                    syms[sym] = var_next
                    var_next += 1
                val = syms[sym]
            out.append(val & 0x7FFF)
        else:
            out.append(parse_c(line))
    return out

instrs = assemble(ASM)
out = os.path.join(os.path.dirname(__file__), 'knightrider.hack')
with open(out, 'wb') as f:
    for i in instrs:
        f.write(struct.pack('>H', i))
print(f"OK: {len(instrs)} Instruktionen → {out}")
