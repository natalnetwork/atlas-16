// =============================================================================
// sprite_engine.sv — Hardware-Sprite-Engine für Atlas 16
//
// Implementiert 16 Hardware-Sprites mit je 16×16 Pixel @ 8bpp.
//
// Funktionsprinzip (Scanline-basiert):
//   Während der horizontalen Austastlücke (H-Blank, nach Pixel 639) wird für
//   jeden aktiven Sprite geprüft, ob er auf der NÄCHSTEN Zeile sichtbar ist.
//   Für sichtbare Sprites wird die Tile-Zeile aus dem SDRAM per DMA geladen
//   und in einem internen Zeilenpuffer gespeichert.
//   Während der aktiven Bildzeit werden alle 16 Sprite-Zeilenpuffer
//   kombinatorisch überlagert (Compositing). Sprite 0 hat die höchste Priorität.
//
// Transparenz:
//   Pixel, deren Farbindex dem Color-Key eines Sprites entsprechen, sind
//   transparent und zeigen den Hintergrund (Framebuffer).
//
// Sprite-Attribute (Register-Offsets relativ zu 0x6100):
//   Sprite n: Basisadresse 0x6100 + n×8
//     Offset +0: X-Position (9-bit, Bits 8:0)
//     Offset +1: Y-Position (8-bit, Bits 7:0)
//     Offset +2: Tile-Adresse Low  (SDRAM-Wortadresse, Bits 15:0)
//     Offset +3: Tile-Adresse High (SDRAM-Wortadresse, Bits 10:0)
//     Offset +4: Flags
//                 Bit 0: aktiv (0 = Sprite wird ignoriert)
//                 Bit 1: flip_x (horizontal spiegeln)
//                 Bit 2: flip_y (vertikal spiegeln)
//                 Bit 3: priorität (1 = hinter dem Framebuffer, 0 = darüber)
//     Offset +5: Color-Key (transparente Farbe, 8-bit)
//     Offset +6: reserviert
//     Offset +7: reserviert
//
// Timing-Voraussetzung:
//   hcount und vcount müssen mit dem vga_controller synchron sein.
//   Die Sprite-Engine läuft mit dem 50 MHz Systemtakt; hcount/vcount
//   kommen aus der 25 MHz Domäne und sind für je 2 Systemtakte stabil.
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module sprite_engine (
    input  logic        clk,        // 50 MHz Systemtakt
    input  logic        rst,

    // -------------------------------------------------------------------------
    // CPU-Register-Interface (sel_sprites aktiv, Adressen 0x6100–0x617F)
    // -------------------------------------------------------------------------
    input  logic  [6:0] reg_addr,   // Bits [6:0] der Speicheradresse (0–127)
    input  logic [15:0] reg_wdata,
    input  logic        reg_write,

    // -------------------------------------------------------------------------
    // VGA-Timing (von vga_controller, 25 MHz Domäne)
    // Die Werte sind für je 2 Systemtakte stabil (keine Metastabilität).
    // -------------------------------------------------------------------------
    input  logic  [9:0] hcount,     // Horizontaler Pixelzähler (0–799)
    input  logic  [9:0] vcount,     // Vertikaler Zeilenzähler  (0–524)

    // -------------------------------------------------------------------------
    // SDRAM-DMA-Interface (Kanal 2, niedrigste Priorität)
    // -------------------------------------------------------------------------
    output logic [26:0] sdram_addr,
    input  logic [15:0] sdram_data,
    output logic        sdram_req,
    input  logic        sdram_ack,

    // -------------------------------------------------------------------------
    // Compositor-Ausgabe (kombinatorisch, synchron mit hcount/vcount)
    // -------------------------------------------------------------------------
    output logic  [7:0] sprite_pixel,   // Farb-Index des vorderen sichtbaren Sprites
    output logic        sprite_valid    // 1 = sprite_pixel gültig (nicht transparent)
);
    // =========================================================================
    // Timing-Konstanten (müssen mit vga_controller.sv übereinstimmen)
    // =========================================================================
    localparam int H_ACTIVE  = 640;   // Ende des aktiven Bereichs
    localparam int H_TOTAL   = 800;   // Gesamte Zeilenbreite in Pixeltakten
    localparam int IMG_X_OFF = 64;    // (640 - 512) / 2 — linker Rand
    localparam int IMG_Y_OFF = 112;   // (480 - 256) / 2 — oberer Rand
    localparam int IMG_W     = 512;
    localparam int IMG_H     = 256;
    localparam int NUM_SPRS  = 16;    // Anzahl der Hardware-Sprites
    localparam int SPR_SIZE  = 16;    // Sprite-Größe in Pixeln (16×16)
    // Bytes pro Sprite-Zeile: 16 Pixel × 1 Byte = 16 Bytes = 8 Worte (16-bit)
    localparam int ROW_WORDS = 8;

    // =========================================================================
    // Sprite-Attribut-Register: 16 Sprites × 8 Register = 128 × 16-bit
    // =========================================================================
    logic [15:0] spr_regs [0:127];

    // Hilfs-Funktionen: Attribute aus spr_regs extrahieren
    // (kombinatorisch, werden in always_comb verwendet)
    //
    // Sprite i: spr_regs[i*8 + k]
    //   k=0: X, k=1: Y, k=2: tile_lo, k=3: tile_hi, k=4: flags, k=5: ckey

    always_ff @(posedge clk) begin
        integer j;
        if (rst) begin
            for (j = 0; j < 128; j = j + 1)
                spr_regs[j] <= 16'h0000;
        end else if (reg_write) begin
            spr_regs[reg_addr] <= reg_wdata;
        end
    end

    // =========================================================================
    // Zeilenpuffer: 16 Sprites × 16 Pixel × 8-bit = 2048 Bit
    // Wird während H-Blank beschrieben, während Aktivbereich gelesen.
    // =========================================================================
    logic [7:0] line_buf [0:NUM_SPRS-1][0:SPR_SIZE-1];

    // =========================================================================
    // Fetch-State-Machine (Fetch-Phase während H-Blank)
    // =========================================================================
    typedef enum logic [2:0] {
        FS_IDLE,        // wartet auf H-Blank (hcount == H_ACTIVE)
        FS_SCAN,        // prüft ob Sprite n auf nächster Zeile sichtbar ist
        FS_FETCH_REQ,   // stellt SDRAM-Leseanfrage für aktuelles Wort
        FS_FETCH_WAIT,  // wartet auf SDRAM ack
        FS_FETCH_STORE, // speichert empfangene Pixel im Zeilenpuffer
        FS_NEXT_SPRITE  // wechselt zum nächsten Sprite
    } fetch_state_t;

    fetch_state_t  fetch_state;
    logic  [3:0]   fetch_spr;    // Index des aktuell bearbeiteten Sprites (0–15)
    logic  [2:0]   fetch_word;   // Wort-Index innerhalb der Tile-Zeile (0–7)
    logic  [3:0]   fetch_tile_row; // Tile-interne Zeile des aktuellen Sprites

    // Attribute des aktuell bearbeiteten Sprites
    logic  [8:0]   cur_spr_x;
    logic  [7:0]   cur_spr_y;
    logic [26:0]   cur_tile_addr;
    logic  [3:0]   cur_flags;
    logic  [7:0]   cur_ckey;
    logic          cur_active;
    logic          cur_flip_x;
    logic          cur_flip_y;

    // Kombinatorisch aus spr_regs extrahieren
    assign cur_spr_x    = spr_regs[{fetch_spr, 3'd0}][8:0];
    assign cur_spr_y    = spr_regs[{fetch_spr, 3'd1}][7:0];
    assign cur_tile_addr= {spr_regs[{fetch_spr, 3'd3}][10:0],
                           spr_regs[{fetch_spr, 3'd2}][15:0]};
    assign cur_flags    = spr_regs[{fetch_spr, 3'd4}][3:0];
    assign cur_ckey     = spr_regs[{fetch_spr, 3'd5}][7:0];
    assign cur_active   = cur_flags[0];
    assign cur_flip_x   = cur_flags[1];
    assign cur_flip_y   = cur_flags[2];

    // Nächste sichtbare Zeile (bei vcount = aktueller Zeile → fetchem für vcount+1)
    logic [9:0] next_vcount;
    assign next_vcount = (vcount == 10'd524) ? 10'd0 : vcount + 10'd1;

    // Ist der Sprite auf der NÄCHSTEN Zeile sichtbar?
    logic [8:0] next_img_y_ext; // 9-bit für vorzeichenlose Berechnung
    logic [8:0] spr_y_ext;
    logic        spr_on_line;
    logic [3:0]  spr_tile_row;

    assign next_img_y_ext = (next_vcount >= IMG_Y_OFF) ?
                            (next_vcount - IMG_Y_OFF) : 9'h1FF; // ungültig wenn außerhalb
    assign spr_y_ext      = {1'b0, cur_spr_y};
    assign spr_on_line    = cur_active &&
                            (next_img_y_ext < IMG_H) &&
                            (next_img_y_ext >= spr_y_ext) &&
                            (next_img_y_ext <  spr_y_ext + SPR_SIZE);
    assign spr_tile_row   = cur_flip_y ?
                            (4'd15 - (next_img_y_ext[3:0] - cur_spr_y[3:0])) :
                            (next_img_y_ext[3:0] - cur_spr_y[3:0]);

    // SDRAM-Adresse für aktuelles Fetch-Wort
    // Tile-Zeilen-Offset: tile_row × ROW_WORDS + fetch_word
    logic [26:0] fetch_sdram_addr;
    assign fetch_sdram_addr = cur_tile_addr +
                              {23'h0, fetch_tile_row} * ROW_WORDS +
                              {24'h0, fetch_word};

    always_ff @(posedge clk) begin
        integer p;
        if (rst) begin
            fetch_state    <= FS_IDLE;
            fetch_spr      <= 4'h0;
            fetch_word     <= 3'h0;
            fetch_tile_row <= 4'h0;
            for (p = 0; p < NUM_SPRS; p = p + 1) begin
                integer q;
                for (q = 0; q < SPR_SIZE; q = q + 1)
                    line_buf[p][q] <= 8'h00;
            end
        end else begin
            unique case (fetch_state)

                FS_IDLE: begin
                    // Starte Fetch-Phase zu Beginn der H-Blank-Periode
                    if (hcount == H_ACTIVE) begin
                        fetch_spr   <= 4'h0;
                        fetch_state <= FS_SCAN;
                    end
                end

                FS_SCAN: begin
                    if (spr_on_line) begin
                        // Sprite auf nächster Zeile sichtbar → Tile-Zeile fetchen
                        fetch_word     <= 3'h0;
                        fetch_tile_row <= spr_tile_row;
                        fetch_state    <= FS_FETCH_REQ;
                    end else begin
                        // Sprite nicht sichtbar → Zeilenpuffer löschen (transparent)
                        fetch_state <= FS_NEXT_SPRITE;
                    end
                end

                FS_FETCH_REQ: begin
                    // SDRAM-Anfrage gestellt (sdram_req kombinatorisch)
                    fetch_state <= FS_FETCH_WAIT;
                end

                FS_FETCH_WAIT: begin
                    if (sdram_ack) begin
                        fetch_state <= FS_FETCH_STORE;
                    end
                end

                FS_FETCH_STORE: begin
                    // 16-bit Wort = 2 Pixel speichern (High-Byte links, Low-Byte rechts)
                    // Pixel-Indizes im Zeilenpuffer: 2×fetch_word und 2×fetch_word+1
                    if (cur_flip_x) begin
                        // Horizontale Spiegelung: Pixel in umgekehrter Reihenfolge
                        line_buf[fetch_spr][SPR_SIZE - 1 - {1'b0, fetch_word, 1'b0}]
                            <= sdram_data[15:8];
                        line_buf[fetch_spr][SPR_SIZE - 1 - {1'b0, fetch_word, 1'b1}]
                            <= sdram_data[7:0];
                    end else begin
                        line_buf[fetch_spr][{1'b0, fetch_word, 1'b0}] <= sdram_data[15:8];
                        line_buf[fetch_spr][{1'b0, fetch_word, 1'b1}] <= sdram_data[7:0];
                    end

                    if (fetch_word == ROW_WORDS - 1) begin
                        // Alle 8 Worte geladen → zum nächsten Sprite
                        fetch_state <= FS_NEXT_SPRITE;
                    end else begin
                        fetch_word  <= fetch_word + 1'b1;
                        fetch_state <= FS_FETCH_REQ;
                    end
                end

                FS_NEXT_SPRITE: begin
                    if (fetch_spr == 4'd15) begin
                        // Alle 16 Sprites abgearbeitet → warte auf nächste H-Blank
                        fetch_state <= FS_IDLE;
                    end else begin
                        fetch_spr   <= fetch_spr + 1'b1;
                        fetch_state <= FS_SCAN;
                    end
                end

                default: fetch_state <= FS_IDLE;
            endcase
        end
    end

    // =========================================================================
    // SDRAM-Interface (nur während Fetch-States aktiv)
    // =========================================================================
    assign sdram_req  = (fetch_state == FS_FETCH_REQ);
    assign sdram_addr = fetch_sdram_addr;

    // =========================================================================
    // Compositor: Kombinatorisches Compositing aller 16 Sprites
    //
    // Wird für jedes Pixel während der aktiven Bildzeit ausgewertet.
    // Sprite 0 hat die höchste Priorität (vorderste Ebene).
    //
    // Voraussetzung: hcount und vcount beschreiben den aktuell
    // AUSZUGEBENDEN Pixel (vor Register-Stufe im vga_controller).
    // =========================================================================
    integer i;
    logic [8:0]  comp_img_x;    // X-Koordinate im 512×256-Bildbereich
    logic [8:0]  comp_img_y;    // Y-Koordinate im 512×256-Bildbereich
    logic        comp_in_image; // Pixel liegt im sichtbaren Bildbereich

    assign comp_img_x   = hcount[8:0] - IMG_X_OFF[8:0];
    assign comp_img_y   = {1'b0, vcount[7:0]} - IMG_Y_OFF[8:0];
    assign comp_in_image = (hcount >= IMG_X_OFF) && (hcount < IMG_X_OFF + IMG_W) &&
                           (vcount >= IMG_Y_OFF) && (vcount < IMG_Y_OFF + IMG_H);

    always_comb begin
        sprite_pixel = 8'h00;
        sprite_valid = 1'b0;

        if (comp_in_image) begin
            // Sprite 15 bis 0 prüfen (Sprite 0 überschreibt alle anderen → höchste Prio)
            for (i = 15; i >= 0; i = i - 1) begin
                // Attribute direkt aus spr_regs lesen
                if (spr_regs[i*8 + 4][0]) begin // aktiv?
                    // Liegt der aktuelle Pixel im X-Bereich dieses Sprites?
                    if ((comp_img_x >= {1'b0, spr_regs[i*8][7:0]}) &&
                        (comp_img_x <  {1'b0, spr_regs[i*8][7:0]} + SPR_SIZE)) begin
                        // Pixel-Index innerhalb des Sprites
                        logic [3:0] px_idx;
                        px_idx = comp_img_x[3:0] - spr_regs[i*8][3:0];
                        if (spr_regs[i*8 + 4][1]) // flip_x
                            px_idx = 4'd15 - px_idx;
                        // Pixel aus Zeilenpuffer lesen
                        begin
                            logic [7:0] px_color;
                            px_color = line_buf[i][px_idx];
                            if (px_color != spr_regs[i*8 + 5][7:0]) begin
                                // Nicht transparent → diesen Sprite ausgeben
                                sprite_pixel = px_color;
                                sprite_valid = 1'b1;
                            end
                        end
                    end
                end
            end
        end
    end

endmodule
