// =============================================================================
// hps_mailbox.sv — HPS-FPGA Kommunikations-Interface (erweitert)
//
// Ermöglicht dem Linux-HPS folgende Operationen:
//   - Programme in den Instruction ROM laden (LOAD_ROM)
//   - CPU zurücksetzen (RESET) / anhalten (HALT)
//   - Echtzeituhr aktualisieren (RTC_UPDATE)
//   - Eingabezustand schreiben (Tastatur, Maus, Gamepad)
//
// Alle Eingabegeräte werden von einem Linux-Daemon (/usr/local/bin/input_daemon)
// aus /dev/input/* gelesen und hier als Register geschrieben. Die CPU liest
// die Werte aus dem normalen Memory-Mapped IO Adressraum (0x6000–0x7FFF).
//
// Register-Map (HPS-Bridge, Byte-Adressen = Offset × 4):
//
//   Offset  Byte-Addr  Name          Beschreibung
//   ──────────────────────────────────────────────────────────────────────────
//   0x00    0x00       MB_CMD        Kommando (HPS → FPGA)
//   0x01    0x04       MB_STATUS     Ausführungsstatus (FPGA → HPS)
//   0x02    0x08       MB_ADDR       ROM-Ladeadresse
//   0x03    0x0C       MB_DATA       ROM-Ladedaten
//   0x04    0x10       MB_RTC        Zeit gepackt: [23:16]=Std, [15:8]=Min, [7:0]=Sek
//   0x05    0x14       KBD_KEY       ASCII-Code der aktuell gedrückten Taste (0=keine)
//   0x06    0x18       MOUSE_X       Maus: absolute X-Position (0–511)
//   0x07    0x1C       MOUSE_Y       Maus: absolute Y-Position (0–255)
//   0x08    0x20       MOUSE_BTN     Maus: Bit0=Links, Bit1=Rechts, Bit2=Mitte,
//                                         Bit3=Tap, Bit15=verbunden
//   0x09    0x24       PAD_BTN       Gamepad: Button-Bitmask (s.u.)
//   0x0A    0x28       PAD_LEFT      Gamepad: Linker Stick  [7:0]=X, [15:8]=Y
//   0x0B    0x2C       PAD_RIGHT     Gamepad: Rechter Stick [7:0]=X, [15:8]=Y
//   0x0C    0x30       PAD_TRG       Gamepad: [7:0]=LT, [15:8]=RT, [16]=verbunden
//
// PAD_BTN Bit-Belegung:
//   Bit  0: A             Bit  4: LB (linke Schulter)
//   Bit  1: B             Bit  5: RB (rechte Schulter)
//   Bit  2: X             Bit  6: Start
//   Bit  3: Y             Bit  7: Back/Select
//   Bit  8: DPad Hoch     Bit 12: LS (linker Stick gedrückt)
//   Bit  9: DPad Runter   Bit 13: RS (rechter Stick gedrückt)
//   Bit 10: DPad Links    Bit 14: Xbox-Taste
//   Bit 11: DPad Rechts   Bit 15: verbunden
//
// CPU-Zugriff auf Eingabewerte (read-only für CPU):
//   0x6000  Tastatur ASCII       (Hack-kompatibel)
//   0x6440  MOUSE_X
//   0x6441  MOUSE_Y
//   0x6442  MOUSE_BTN
//   0x6460  PAD_BTN
//   0x6461  PAD_LEFT
//   0x6462  PAD_RIGHT
//   0x6463  PAD_TRG
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module hps_mailbox (
    input  logic        clk,
    input  logic        rst,

    // -------------------------------------------------------------------------
    // HPS-to-FPGA Lightweight Bridge (5-bit Wortadresse = 32 Register)
    // Linux-Basisadresse: 0xFF200000
    // -------------------------------------------------------------------------
    input  logic  [4:0] hps_addr,
    input  logic [31:0] hps_wdata,
    input  logic        hps_write,
    input  logic        hps_read,
    output logic [31:0] hps_rdata,

    // -------------------------------------------------------------------------
    // CPU-Reset und Halt
    // -------------------------------------------------------------------------
    output logic        cpu_rst,
    output logic        cpu_halt,

    // -------------------------------------------------------------------------
    // ROM-Lade-Interface
    // -------------------------------------------------------------------------
    output logic [14:0] rom_wr_addr,
    output logic [15:0] rom_wr_data,
    output logic        rom_wr_en,

    // -------------------------------------------------------------------------
    // RTC-Update-Interface
    // -------------------------------------------------------------------------
    output logic [7:0]  rtc_sec,
    output logic [7:0]  rtc_min,
    output logic [7:0]  rtc_hour,
    output logic        rtc_update,

    // -------------------------------------------------------------------------
    // Tastatur (→ CPU 0x6000, Hack-kompatibel)
    // -------------------------------------------------------------------------
    output logic [15:0] kbd_key,    // ASCII-Code (0 = keine Taste)

    // -------------------------------------------------------------------------
    // Maus / Trackpad (→ CPU 0x6440–0x6442)
    // -------------------------------------------------------------------------
    output logic [15:0] mouse_x,    // Absolute X-Position (0–511)
    output logic [15:0] mouse_y,    // Absolute Y-Position (0–255)
    output logic [15:0] mouse_btn,  // Buttons + connected-Flag

    // -------------------------------------------------------------------------
    // Gamepad (→ CPU 0x6460–0x6463)
    // -------------------------------------------------------------------------
    output logic [15:0] pad_btn,    // Button-Bitmask (s. Kommentar oben)
    output logic [15:0] pad_left,   // Linker Stick  [7:0]=X [15:8]=Y
    output logic [15:0] pad_right,  // Rechter Stick [7:0]=X [15:8]=Y
    output logic [15:0] pad_trg,    // Trigger + verbunden-Flag

    // -------------------------------------------------------------------------
    // Quittierungssignal (FPGA → Mailbox)
    // -------------------------------------------------------------------------
    input  logic        cmd_done
);
    // =========================================================================
    // Kommandocodes
    // =========================================================================
    localparam logic [7:0] CMD_NONE       = 8'h00;
    localparam logic [7:0] CMD_RESET      = 8'h01;
    localparam logic [7:0] CMD_LOAD_ROM   = 8'h02;
    localparam logic [7:0] CMD_RTC_UPDATE = 8'h03;
    localparam logic [7:0] CMD_HALT       = 8'h04;

    // =========================================================================
    // Interne Register
    // =========================================================================
    logic  [7:0] mb_cmd;
    logic  [7:0] mb_status;
    logic [14:0] mb_addr;
    logic [15:0] mb_data;
    logic [23:0] mb_rtc;
    // Eingabe-Register (nur von HPS geschrieben)
    logic [15:0] mb_kbd;
    logic [15:0] mb_mouse_x, mb_mouse_y, mb_mouse_btn;
    logic [15:0] mb_pad_btn, mb_pad_left, mb_pad_right, mb_pad_trg;

    // =========================================================================
    // HPS schreibt Mailbox-Register
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            mb_cmd      <= CMD_NONE;
            mb_status   <= 8'h00;
            mb_addr     <= '0;
            mb_data     <= '0;
            mb_rtc      <= '0;
            mb_kbd      <= 16'h0000;
            mb_mouse_x  <= 16'd256;  // Start: Mitte des 512er-Bildbereichs
            mb_mouse_y  <= 16'd128;  // Start: Mitte des 256er-Bildbereichs
            mb_mouse_btn<= 16'h0000;
            mb_pad_btn  <= 16'h0000;
            mb_pad_left <= 16'h8080; // Start: beide Sticks in Mittelposition
            mb_pad_right<= 16'h8080;
            mb_pad_trg  <= 16'h0000;
        end else begin
            if (hps_write) begin
                unique case (hps_addr)
                    5'h00: mb_cmd       <= hps_wdata[7:0];
                    5'h02: mb_addr      <= hps_wdata[14:0];
                    5'h03: mb_data      <= hps_wdata[15:0];
                    5'h04: mb_rtc       <= hps_wdata[23:0];
                    5'h05: mb_kbd       <= hps_wdata[15:0];
                    5'h06: mb_mouse_x   <= hps_wdata[15:0];
                    5'h07: mb_mouse_y   <= hps_wdata[15:0];
                    5'h08: mb_mouse_btn <= hps_wdata[15:0];
                    5'h09: mb_pad_btn   <= hps_wdata[15:0];
                    5'h0A: mb_pad_left  <= hps_wdata[15:0];
                    5'h0B: mb_pad_right <= hps_wdata[15:0];
                    5'h0C: mb_pad_trg   <= hps_wdata[15:0];
                    default: ;
                endcase
            end
            // Kommandoquittierung
            if (cmd_done)
                mb_status <= 8'h01;
            if (mb_status == 8'h01 && !hps_write)
                mb_cmd <= CMD_NONE;
        end
    end

    // =========================================================================
    // HPS liest Statusregister
    // =========================================================================
    always_comb begin
        unique case (hps_addr)
            5'h00:   hps_rdata = {24'h0, mb_cmd};
            5'h01:   hps_rdata = {24'h0, mb_status};
            5'h02:   hps_rdata = {17'h0, mb_addr};
            5'h03:   hps_rdata = {16'h0, mb_data};
            5'h04:   hps_rdata = {8'h0,  mb_rtc};
            5'h05:   hps_rdata = {16'h0, mb_kbd};
            5'h06:   hps_rdata = {16'h0, mb_mouse_x};
            5'h07:   hps_rdata = {16'h0, mb_mouse_y};
            5'h08:   hps_rdata = {16'h0, mb_mouse_btn};
            5'h09:   hps_rdata = {16'h0, mb_pad_btn};
            5'h0A:   hps_rdata = {16'h0, mb_pad_left};
            5'h0B:   hps_rdata = {16'h0, mb_pad_right};
            5'h0C:   hps_rdata = {16'h0, mb_pad_trg};
            default: hps_rdata = 32'h0;
        endcase
    end

    // =========================================================================
    // Kommando-Ausführung (kombinatorisch)
    // =========================================================================
    always_comb begin
        cpu_rst     = 1'b0;
        cpu_halt    = 1'b0;
        rom_wr_en   = 1'b0;
        rom_wr_addr = mb_addr;
        rom_wr_data = mb_data;
        rtc_sec     = mb_rtc[7:0];
        rtc_min     = mb_rtc[15:8];
        rtc_hour    = mb_rtc[23:16];
        rtc_update  = 1'b0;

        unique case (mb_cmd)
            CMD_RESET:      cpu_rst    = 1'b1;
            CMD_LOAD_ROM:   rom_wr_en  = 1'b1;
            CMD_RTC_UPDATE: rtc_update = 1'b1;
            CMD_HALT:       cpu_halt   = 1'b1;
            default: ;
        endcase
    end

    // =========================================================================
    // Eingabewerte direkt als Ausgänge (für CPU-MMIO-Verdrahtung im Toplevel)
    // =========================================================================
    assign kbd_key   = mb_kbd;
    assign mouse_x   = mb_mouse_x;
    assign mouse_y   = mb_mouse_y;
    assign mouse_btn = mb_mouse_btn;
    assign pad_btn   = mb_pad_btn;
    assign pad_left  = mb_pad_left;
    assign pad_right = mb_pad_right;
    assign pad_trg   = mb_pad_trg;

endmodule
