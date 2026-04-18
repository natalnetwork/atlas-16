# Atlas 16 — Claude Code Projektanweisungen

## Aktive Skills für dieses Projekt

Beide Skills zu Beginn jeder Session lesen und anwenden:

- `~/Dokumente/CLAUDE-Skills/SystemVerilog.md` — SV-2005 Sprachregeln und RTL-Codierungsrichtlinien
- `~/Dokumente/CLAUDE-Skills/DE10-Nano.md` — Board-Workflow, Pin-Planung, Bring-Up, JTAG, SDRAM

## Projekt-Spezifika (nicht in den Skills enthalten)

- Standard: IEEE 1800-2005 — kein SV-2009/2012 (Quartus Lite)
- Board: Terasic DE10-Nano, Cyclone V 5CSEBA6U23I7
- Takt: 50 MHz vom Board
- Reset: aktiv-Low, `always_ff @(posedge clk, negedge resetN)`
- Kein 3rd-Party-Code — nur Intel/Altera IP-Kerne aus Quartus (altsyncram, altpll, etc.)
- SDRAM: externes 128 MB Modul auf GPIO-Header, FPGA-seitig (kein HPS-DDR3)
- Architektur: Hack+ (Nand2Tetris), Harvard, Memory-Mapped IO, 16-Bit wortadressiert
