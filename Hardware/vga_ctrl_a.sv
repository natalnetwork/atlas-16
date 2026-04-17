// =============================================================================
// vga_ctrl_a.sv — VGA/HDMI-Controller für Atlas 16 Stufe A (1bpp)
//
// Erzeugt ein 512×256 Pixel Monochrom-Bild (1bpp), zentriert in 640×480.
//
// Timing: 640×480 @ 60 Hz (Standard VGA)
//   Pixeltakt: 25 MHz (50 MHz / 2, ausreichend für Entwicklung)
//   Das 512×256 Bild wird zentriert dargestellt (64px Rand links/rechts,
//   112px Rand oben/unten).
//
// Framebuffer-Zugriff:
//   Liest direkt aus dem LUTRAM-Framebuffer in hack_ram_a über einen
//   kombinatorischen Lesepfad. Kein SDRAM, kein Shift-Register-Prefetch.
//   Adresse: { img_y[7:0], img_x[8:4] } = Zeilennr. * 32 + Spaltengruppe
//   Bit:     img_x[3:0] — LSB = linkster Pixel der Gruppe (Hack-kompatibel)
//
// Ausgabe: Paralleles RGB an ADV7513 HDMI-Chip des DE10-Nano
//   Hinweis: Der ADV7513 muss vor dem ersten Bild per I2C initialisiert
//   werden (von HPS Linux aus, z.B. via i2cset).
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module vga_ctrl_a (
    input  logic        clk_25mhz,  // 25 MHz Pixeltakt
    input  logic        rst,

    // -------------------------------------------------------------------------
    // Framebuffer-Lesepfad (kombinatorisch, aus hack_ram_a)
    // -------------------------------------------------------------------------
    output logic [12:0] fb_rd_addr, // Wort-Adresse im Framebuffer (0–8191)
    input  logic [15:0] fb_rd_data, // 16 Pixel (1bpp) — LSB = linkster Pixel

    // -------------------------------------------------------------------------
    // HDMI-Ausgabe (an ADV7513 des DE10-Nano)
    // -------------------------------------------------------------------------
    output logic        hsync,
    output logic        vsync,
    output logic        de,         // Data Enable
    output logic [23:0] hdmi_d,     // RGB 8-8-8

    // -------------------------------------------------------------------------
    // Scan-Position (für spätere Erweiterungen, z.B. Sprites)
    // -------------------------------------------------------------------------
    output logic  [9:0] hcount,
    output logic  [9:0] vcount
);
    // =========================================================================
    // VGA 640×480 @ 60 Hz Timing-Parameter (Pixeltakt 25 MHz)
    // =========================================================================
    localparam int H_ACTIVE = 640;
    localparam int H_FP     = 16;   // Front Porch
    localparam int H_SYNC   = 96;   // Sync-Puls
    localparam int H_BP     = 48;   // Back Porch
    localparam int H_TOTAL  = 800;  // Gesamt: 640+16+96+48

    localparam int V_ACTIVE = 480;
    localparam int V_FP     = 10;
    localparam int V_SYNC   = 2;
    localparam int V_BP     = 33;
    localparam int V_TOTAL  = 525;  // Gesamt: 480+10+2+33

    // 512×256 Bild zentriert in 640×480
    localparam int IMG_X_OFF = 64;  // (640 - 512) / 2
    localparam int IMG_Y_OFF = 112; // (480 - 256) / 2

    // =========================================================================
    // Horizontale und vertikale Zähler
    // =========================================================================
    logic [9:0] h_cnt;
    logic [9:0] v_cnt;

    assign hcount = h_cnt;
    assign vcount = v_cnt;

    always_ff @(posedge clk_25mhz) begin
        if (rst) begin
            h_cnt <= 10'd0;
            v_cnt <= 10'd0;
        end else begin
            if (h_cnt == H_TOTAL - 1) begin
                h_cnt <= 10'd0;
                v_cnt <= (v_cnt == V_TOTAL - 1) ? 10'd0 : v_cnt + 10'd1;
            end else begin
                h_cnt <= h_cnt + 10'd1;
            end
        end
    end

    // =========================================================================
    // Bildkoordinaten (kombinatorisch)
    // img_x: 0–511, img_y: 0–255 — nur gültig wenn in_image = true
    // =========================================================================
    logic        in_image;
    logic  [9:0] img_x_wide; // 10-bit Differenz für korrekte Subtraktion
    logic  [9:0] img_y_wide;
    logic  [8:0] img_x;      // 0–511
    logic  [7:0] img_y;      // 0–255

    assign in_image   = (h_cnt >= IMG_X_OFF) && (h_cnt < IMG_X_OFF + 512) &&
                        (v_cnt >= IMG_Y_OFF) && (v_cnt < IMG_Y_OFF + 256);

    assign img_x_wide = h_cnt - 10'(IMG_X_OFF);
    assign img_y_wide = v_cnt - 10'(IMG_Y_OFF);
    assign img_x      = img_x_wide[8:0];
    assign img_y      = img_y_wide[7:0];

    // =========================================================================
    // Framebuffer-Adresse und Pixel (kombinatorisch)
    //
    // Framebuffer-Layout (Hack-kompatibel):
    //   Wort-Adresse = Zeile * 32 + Spaltengruppe (Spalte / 16)
    //   Bit-Position = Spalte % 16 (Bit 0 = linkster Pixel)
    //
    // fb_rd_addr nur gültig wenn in_image = true, aber kombinatorisch
    // berechnet — außerhalb liest VGA aus zufälliger Adresse (kein Problem,
    // da Ausgabe durch pixel_out = 0 bei !in_image unterdrückt wird).
    // =========================================================================
    assign fb_rd_addr = {img_y, img_x[8:4]};   // img_y*32 + img_x/16, 13 Bit

    logic pixel_val;
    assign pixel_val = fb_rd_data[img_x[3:0]];  // Bit 0 = linkster Pixel

    // =========================================================================
    // Ausgabe-Register (alle Ausgaben synchron — gleiche Latenz → ausgerichtet)
    // =========================================================================
    always_ff @(posedge clk_25mhz) begin
        if (rst) begin
            hsync  <= 1'b1;
            vsync  <= 1'b1;
            de     <= 1'b0;
            hdmi_d <= 24'h000000;
        end else begin
            // Sync-Signale (aktiv-niedrig bei Standard-VGA)
            hsync <= ~(h_cnt >= (H_ACTIVE + H_FP) &&
                       h_cnt <  (H_ACTIVE + H_FP + H_SYNC));
            vsync <= ~(v_cnt >= (V_ACTIVE + V_FP) &&
                       v_cnt <  (V_ACTIVE + V_FP + V_SYNC));

            // Data Enable: aktiv im sichtbaren Bereich
            de <= (h_cnt < H_ACTIVE) && (v_cnt < V_ACTIVE);

            // TEST: weißes Bild im aktiven Bereich (Framebuffer-Lesepfad deaktiviert)
            // → Quartus optimiert das MLAB heraus, Compile-Zeit sinkt drastisch
            // → Wenn HDMI Signal kommt: I2C-Init funktioniert
            hdmi_d <= in_image ? 24'hFFFFFF : 24'h000000;
        end
    end

endmodule
