// =============================================================================
// vga_controller.sv — VGA/HDMI-Controller für den Atlas 16
//
// Erzeugt ein 512×256 Pixel Bild mit zwei Modi:
//
//   VGA_MODE = 0  Legacy Hack:  1bpp, 512×256, 2 Farben aus Palette
//   VGA_MODE = 1  Atlas 16:     8bpp, 512×256, 256 Farben (RGB 3-3-2)
//
// Timing: 640×480 @ 60 Hz (Standard VGA)
//   Das 512×256 Bild wird zentriert dargestellt.
//   Pixeltakt: 25,175 MHz (erzeugt durch PLL aus 50 MHz)
//
// Double Buffering:
//   fb_base zeigt auf den sichtbaren Frame im SDRAM.
//   Die CPU zeichnet in den unsichtbaren Back-Buffer.
//   Mit zwei Register-Schreibvorgängen wird umgeschaltet.
//
// SDRAM-Zugriff: Kanal 1 des SDRAM-Controllers (DMA, kein CPU-Aufwand)
//
// Ausgabe: Paralleles RGB an ADV7513 HDMI-Chip des DE10-Nano
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module vga_controller (
    input  logic        clk_25mhz,
    input  logic        rst,

    // -------------------------------------------------------------------------
    // Konfiguration (über Memory-Mapped Register)
    // -------------------------------------------------------------------------
    input  logic        vga_mode,       // 0=1bpp Legacy,  1=8bpp Color
    input  logic [26:0] fb_base,        // SDRAM-Basisadresse des Front-Buffers
    input  logic [7:0]  palette_0,      // Legacy-Modus: Farbe für Bit=0
    input  logic [7:0]  palette_1,      // Legacy-Modus: Farbe für Bit=1

    // -------------------------------------------------------------------------
    // SDRAM-DMA-Interface (Kanal 1, read-only)
    // -------------------------------------------------------------------------
    output logic [26:0] sdram_addr,
    input  logic [15:0] sdram_data,
    output logic        sdram_req,
    input  logic        sdram_ack,

    // -------------------------------------------------------------------------
    // HDMI/VGA-Ausgabe (an ADV7513 des DE10-Nano)
    // -------------------------------------------------------------------------
    output logic        hsync,
    output logic        vsync,
    output logic        de,             // Data Enable (1 im aktiven Bereich)
    output logic [7:0]  r,
    output logic [7:0]  g,
    output logic [7:0]  b,

    // -------------------------------------------------------------------------
    // Timing-Ausgaben (für Sprite Engine und andere Slaves)
    // -------------------------------------------------------------------------
    output logic  [9:0] hcount,         // Horizontaler Pixelzähler (0–799)
    output logic  [9:0] vcount,         // Vertikaler Zeilenzähler  (0–524)

    // -------------------------------------------------------------------------
    // Sprite-Compositor-Eingang (von sprite_engine)
    // Sprite-Pixel werden vor dem Hintergrund-Pixel dargestellt.
    // -------------------------------------------------------------------------
    input  logic  [7:0] sprite_pixel,   // Sprite-Farb-Index
    input  logic        sprite_valid    // 1 = Sprite-Pixel sichtbar
);
    // =========================================================================
    // VGA 640×480 @ 60 Hz Timing-Parameter
    // Pixeltakt: 25,175 MHz
    // =========================================================================
    localparam int H_ACTIVE    = 640;
    localparam int H_FP        = 16;    // Horizontal Front Porch
    localparam int H_SYNC      = 96;    // Horizontal Sync Puls
    localparam int H_BP        = 48;    // Horizontal Back Porch
    localparam int H_TOTAL     = H_ACTIVE + H_FP + H_SYNC + H_BP; // 800

    localparam int V_ACTIVE    = 480;
    localparam int V_FP        = 10;    // Vertical Front Porch
    localparam int V_SYNC      = 2;     // Vertical Sync Puls
    localparam int V_BP        = 33;    // Vertical Back Porch
    localparam int V_TOTAL     = V_ACTIVE + V_FP + V_SYNC + V_BP; // 525

    // Das 512×256 Bild wird in der Mitte des 640×480 Rahmens platziert
    localparam int IMG_W       = 512;
    localparam int IMG_H       = 256;
    localparam int IMG_X_OFF   = (H_ACTIVE - IMG_W) / 2;  // 64 Pixel Rand
    localparam int IMG_Y_OFF   = (V_ACTIVE - IMG_H) / 2;  // 112 Pixel Rand

    // Im 8bpp-Modus: jedes Pixel ist 1 Byte → 2 Pixel pro 16-bit SDRAM-Wort
    // Im 1bpp-Modus: 16 Pixel pro 16-bit SDRAM-Wort

    // =========================================================================
    // Zähler für horizontale und vertikale Position
    // =========================================================================
    logic [9:0] h_cnt;  // 0–799
    logic [9:0] v_cnt;  // 0–524

    // Zähler als Ausgänge weiterleiten (für Sprite Engine etc.)
    assign hcount = h_cnt;
    assign vcount = v_cnt;

    always_ff @(posedge clk_25mhz) begin
        if (rst) begin
            h_cnt <= '0;
            v_cnt <= '0;
        end else begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= '0;
                if (v_cnt == V_TOTAL - 1)
                    v_cnt <= '0;
                else
                    v_cnt <= v_cnt + 1;
            end else begin
                h_cnt <= h_cnt + 1;
            end
        end
    end

    // =========================================================================
    // Sync-Signale erzeugen
    // HSYNC und VSYNC sind aktiv-niedrig bei Standard-VGA
    // =========================================================================
    always_ff @(posedge clk_25mhz) begin
        hsync <= ~(h_cnt >= (H_ACTIVE + H_FP) &&
                   h_cnt <  (H_ACTIVE + H_FP + H_SYNC));
        vsync <= ~(v_cnt >= (V_ACTIVE + V_FP) &&
                   v_cnt <  (V_ACTIVE + V_FP + V_SYNC));
    end

    // =========================================================================
    // Aktiver Bereich: ist der aktuelle Pixel im sichtbaren Bild?
    // =========================================================================
    logic h_active, v_active, pixel_active;
    logic in_image;     // Pixel liegt innerhalb des 512×256 Bildbereichs

    assign h_active   = (h_cnt < H_ACTIVE);
    assign v_active   = (v_cnt < V_ACTIVE);
    assign pixel_active = h_active && v_active;

    // Bildkoordinaten (relativ zum 512×256 Bildbereich)
    logic [8:0] img_x;  // 0–511
    logic [7:0] img_y;  // 0–255

    assign in_image = (h_cnt >= IMG_X_OFF && h_cnt < IMG_X_OFF + IMG_W) &&
                      (v_cnt >= IMG_Y_OFF && v_cnt < IMG_Y_OFF + IMG_H);
    assign img_x    = h_cnt[8:0] - IMG_X_OFF[8:0];
    assign img_y    = v_cnt[7:0] - IMG_Y_OFF[7:0];

    assign de = pixel_active;

    // =========================================================================
    // Pixel-FIFO und SDRAM-Prefetch
    //
    // Der VGA-Controller muss Pixel pünktlich liefern.
    // Strategie: Am Anfang jeder Zeile die benötigten Worte aus dem
    // SDRAM vorab lesen und in einem Schieberegister (shift register)
    // puffern.
    //
    // 8bpp-Modus: 512 Pixel / 2 Pixel/Wort = 256 SDRAM-Lesevorgänge pro Zeile
    // 1bpp-Modus: 512 Pixel / 16 Pixel/Wort = 32 SDRAM-Lesevorgänge pro Zeile
    // =========================================================================

    // Pixel-Schieberegister: 16-bit Wort wird schrittweise ausgegeben
    logic [15:0] pixel_shift_reg;
    logic  [3:0] shift_cnt;         // Zählt verbleibende Pixel im Register

    // SDRAM-Leseadresse (Wort-adresse im Framebuffer)
    logic [26:0] read_addr;

    // Aktueller Pixel-Farbwert (8-bit Index)
    logic [7:0]  pixel_color;

    // =========================================================================
    // SDRAM-Anfrage-Logik
    // =========================================================================
    always_ff @(posedge clk_25mhz) begin
        if (rst) begin
            shift_cnt   <= '0;
            read_addr   <= fb_base;
            sdram_req   <= 1'b0;
        end else begin
            // Neues Bild: Leseadresse zurücksetzen
            if (v_cnt == 0 && h_cnt == 0)
                read_addr <= fb_base;

            // Schieberegister füllen wenn leer und wir im Bild sind
            if (in_image) begin
                if (shift_cnt == 0) begin
                    // Neues 16-bit Wort aus SDRAM anfordern
                    sdram_req <= 1'b1;
                    if (sdram_ack) begin
                        pixel_shift_reg <= sdram_data;
                        read_addr       <= read_addr + 1;
                        sdram_req       <= 1'b0;
                        // 8bpp: 2 Pixel/Wort, 1bpp: 16 Pixel/Wort
                        shift_cnt       <= vga_mode ? 4'd2 : 4'd16;
                    end
                end else begin
                    // Pixel aus Schieberegister auslesen
                    if (vga_mode) begin
                        // 8bpp: jeweils 8 Bit = 1 Pixel
                        pixel_color     <= pixel_shift_reg[7:0];
                        pixel_shift_reg <= {8'h00, pixel_shift_reg[15:8]};
                    end else begin
                        // 1bpp: jeweils 1 Bit = 1 Pixel → Palette
                        pixel_color     <= pixel_shift_reg[0] ? palette_1 : palette_0;
                        pixel_shift_reg <= {1'b0, pixel_shift_reg[15:1]};
                    end
                    shift_cnt <= shift_cnt - 1;
                end
            end else begin
                sdram_req <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Farb-Dekodierung mit Sprite-Compositing
    //
    // Priorität: Sprite (sprite_valid=1) vor Hintergrund (pixel_color)
    // 8bpp RGB-3-3-2: Bits [7:5]=R, [4:2]=G, [1:0]=B
    // Ausgabe: 8-bit pro Kanal (Bit-Replikation für gleichmäßige Skalierung)
    // =========================================================================
    logic [7:0] final_color;
    assign final_color = (in_image && sprite_valid) ? sprite_pixel : pixel_color;

    always_ff @(posedge clk_25mhz) begin
        if (!pixel_active || !in_image) begin
            r <= 8'h00;
            g <= 8'h00;
            b <= 8'h00;
        end else begin
            // RGB 3-3-2 → 8-8-8 (Bit-Replikation für gleichmäßige Skalierung)
            r <= {final_color[7:5], final_color[7:5], final_color[7:6]};
            g <= {final_color[4:2], final_color[4:2], final_color[4:3]};
            b <= {final_color[1:0], final_color[1:0], final_color[1:0],
                  final_color[1:0]};
        end
    end

    // SDRAM-Adresse ausgeben
    assign sdram_addr = read_addr;

endmodule
