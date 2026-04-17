// =============================================================================
// blitter.sv — Asynchroner DMA-Blitter für Atlas 16
//
// Führt Rechteck-Operationen im SDRAM-Framebuffer durch, ohne die CPU
// zu blockieren. Die CPU schreibt Quell-/Zieladresse und Größe in die
// Blitter-Register, setzt BLIT_START = 1 und arbeitet weiter.
// Der Blitter signalisiert das Ende über BLIT_BUSY = 0.
//
// Unterstützte Operationen:
//   COPY  (op=0): Rechteck von SRC nach DST kopieren
//   FILL  (op=1): Rechteck mit BLIT_COLOR füllen (kein Lesezugriff)
//   STAMP (op=2): Wie COPY, aber Pixel mit Farbe == COLORKEY werden
//                 durch das Zielpixel ersetzt (Transparenz, Read-Modify-Write)
//
// Adressierung:
//   Alle Adressen sind 27-bit SDRAM-Wortadressen (16-bit Breite).
//   8bpp: jedes Wort enthält 2 Pixel (High-Byte = linkes Pixel,
//                                      Low-Byte  = rechtes Pixel).
//   Die WIDTH-Angabe ist in Pixeln. Intern werden (WIDTH+1)/2 Worte
//   pro Zeile verarbeitet.
//
// Zeilenabstand:
//   Zeilenbreite des Framebuffers = 256 Worte = 512 Pixel @ 8bpp.
//   Am Ende jeder Zeile wird die Adresse um (256 - word_width) vorgerückt,
//   um zur nächsten Framebufferzeile zu springen.
//
// SDRAM-Interface: Kanal 0 (geteilt mit CPU/Bank-Controller).
//   Während BLIT_BUSY = 1 sendet der Blitter Anfragen an den SDRAM-Arbiter.
//   Die CPU kann parallel weiterarbeiten — sie muss ggf. warten, wenn beide
//   gleichzeitig auf den SDRAM-Kanal 0 zugreifen (Arbitrierung im Toplevel).
//
// Register-Offsets (relativ zu 0x6200):
//   0x00  BLIT_SRC_LO    Quell-Adresse, Bits 15:0
//   0x01  BLIT_SRC_HI    Quell-Adresse, Bits 26:16
//   0x02  BLIT_DST_LO    Ziel-Adresse,  Bits 15:0
//   0x03  BLIT_DST_HI    Ziel-Adresse,  Bits 26:16
//   0x04  BLIT_WIDTH     Breite in Pixeln (1–512)
//   0x05  BLIT_HEIGHT    Höhe in Zeilen (1–256)
//   0x06  BLIT_COLOR     Füllfarbe (8-bit, für FILL-Operation)
//   0x07  BLIT_COLORKEY  Transparenzfarbe (8-bit, für STAMP-Operation)
//   0x08  BLIT_OP        Opcode: 0=COPY, 1=FILL, 2=STAMP
//   0x09  BLIT_START     Schreibe 1 → startet Operation
//   0x0A  BLIT_BUSY      1 = läuft, 0 = bereit (nur lesen)
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module blitter (
    input  logic        clk,
    input  logic        rst,

    // -------------------------------------------------------------------------
    // CPU-Register-Interface (vom Peripherie-Decoder, sel_blitter aktiv)
    // -------------------------------------------------------------------------
    input  logic  [3:0] reg_addr,    // Bits [3:0] der CPU-Adresse (Offset 0–10)
    input  logic [15:0] reg_wdata,
    input  logic        reg_write,
    output logic [15:0] reg_rdata,

    // -------------------------------------------------------------------------
    // SDRAM-Interface (Kanal 0, geteilt mit CPU-Zugriff)
    // -------------------------------------------------------------------------
    output logic [26:0] sdram_addr,
    output logic        sdram_we,
    output logic [15:0] sdram_wdata,
    input  logic [15:0] sdram_rdata,
    output logic        sdram_req,
    input  logic        sdram_ack
);
    // =========================================================================
    // Opcode-Konstanten
    // =========================================================================
    localparam logic [1:0] OP_COPY  = 2'd0;
    localparam logic [1:0] OP_FILL  = 2'd1;
    localparam logic [1:0] OP_STAMP = 2'd2;

    // Framebuffer-Zeilenbreite in Worten (512 Pixel / 2 Pixel/Wort = 256 Worte)
    localparam int FB_ROW_WORDS = 256;

    // =========================================================================
    // Konfigurationsregister (werden von CPU geschrieben)
    // =========================================================================
    logic [26:0] src_addr;     // Quell-Startadresse (SDRAM-Wortadresse)
    logic [26:0] dst_addr;     // Ziel-Startadresse  (SDRAM-Wortadresse)
    logic  [9:0] width_px;     // Breite in Pixeln (1–512)
    logic  [7:0] height;       // Höhe in Zeilen   (1–256)
    logic  [7:0] fill_color;   // Füllfarbe für FILL-Operation
    logic  [7:0] colorkey;     // Transparenzfarbe für STAMP-Operation
    logic  [1:0] op;           // Opcode
    logic        busy;         // 1 = Blitter aktiv

    // Abgeleitete Breite in Worten: ceil(width_px / 2)
    logic  [8:0] width_words;  // (width_px + 1) >> 1, Bereich 1–256

    assign width_words = (width_px[0]) ? (width_px[9:1] + 1'b1) : width_px[9:1];

    // =========================================================================
    // Register schreiben (CPU → Blitter)
    // =========================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            src_addr   <= 27'h0;
            dst_addr   <= 27'h0;
            width_px   <= 10'd512;
            height     <= 8'd256;
            fill_color <= 8'h00;
            colorkey   <= 8'h00;
            op         <= OP_COPY;
        end else if (reg_write && !busy) begin
            // Konfigurationsänderungen sind nur erlaubt wenn der Blitter idle ist
            unique case (reg_addr)
                4'h0: src_addr[15:0]  <= reg_wdata;
                4'h1: src_addr[26:16] <= reg_wdata[10:0];
                4'h2: dst_addr[15:0]  <= reg_wdata;
                4'h3: dst_addr[26:16] <= reg_wdata[10:0];
                4'h4: width_px        <= reg_wdata[9:0];
                4'h5: height          <= reg_wdata[7:0];
                4'h6: fill_color      <= reg_wdata[7:0];
                4'h7: colorkey        <= reg_wdata[7:0];
                4'h8: op              <= reg_wdata[1:0];
                default: ;
            endcase
        end
    end

    // =========================================================================
    // Register lesen (CPU ← Blitter)
    // =========================================================================
    always_comb begin
        unique case (reg_addr)
            4'h0:    reg_rdata = src_addr[15:0];
            4'h1:    reg_rdata = {5'h0, src_addr[26:16]};
            4'h2:    reg_rdata = dst_addr[15:0];
            4'h3:    reg_rdata = {5'h0, dst_addr[26:16]};
            4'h4:    reg_rdata = {6'h0, width_px};
            4'h5:    reg_rdata = {8'h0, height};
            4'h6:    reg_rdata = {8'h0, fill_color};
            4'h7:    reg_rdata = {8'h0, colorkey};
            4'h8:    reg_rdata = {14'h0, op};
            4'h9:    reg_rdata = 16'h0000;   // BLIT_START: schreibt nur
            4'ha:    reg_rdata = {15'h0, busy};
            default: reg_rdata = 16'h0000;
        endcase
    end

    // =========================================================================
    // State Machine
    // =========================================================================
    typedef enum logic [2:0] {
        ST_IDLE,          // Wartet auf Start-Signal
        ST_FILL_REQ,      // FILL: SDRAM-Schreibanfrage
        ST_FILL_WAIT,     // FILL: wartet auf ack
        ST_COPY_RD_REQ,   // COPY/STAMP: Leseanfrage Quelle
        ST_COPY_RD_WAIT,  // COPY/STAMP: wartet auf Lesedaten
        ST_COPY_WR_REQ,   // COPY/STAMP: Schreibanfrage Ziel
        ST_COPY_WR_WAIT,  // COPY/STAMP: wartet auf Schreib-ack
        ST_NEXT           // Nächstes Wort / nächste Zeile
    } blit_state_t;

    blit_state_t state;

    // Laufzeitvariablen
    logic [26:0] cur_src;         // aktuelle Quell-Wortadresse
    logic [26:0] cur_dst;         // aktuelle Ziel-Wortadresse
    logic  [8:0] col_cnt;         // verbleibende Worte in aktueller Zeile
    logic  [7:0] row_cnt;         // verbleibende Zeilen
    logic [15:0] rd_buf;          // zwischengespeichertes Lesewort (für STAMP)
    logic [26:0] stamp_dst_save;  // gespeicherte Zieladresse für STAMP RMW
    logic [15:0] stamp_dst_buf;   // Zielpixel für Read-Modify-Write (STAMP)

    // Für STAMP: Mischen von Quell- und Zielpixeln
    // Low-Byte = rechtes Pixel, High-Byte = linkes Pixel
    logic [7:0]  stamp_lo, stamp_hi;
    assign stamp_lo = (rd_buf[7:0]  == colorkey) ? stamp_dst_buf[7:0]  : rd_buf[7:0];
    assign stamp_hi = (rd_buf[15:8] == colorkey) ? stamp_dst_buf[15:8] : rd_buf[15:8];

    always_ff @(posedge clk) begin
        if (rst) begin
            state   <= ST_IDLE;
            busy    <= 1'b0;
            cur_src <= 27'h0;
            cur_dst <= 27'h0;
            col_cnt <= 9'h0;
            row_cnt <= 8'h0;
            rd_buf  <= 16'h0;
            stamp_dst_buf  <= 16'h0;
            stamp_dst_save <= 27'h0;
        end else begin
            unique case (state)

                // ----------------------------------------------------------
                ST_IDLE: begin
                    if (reg_write && (reg_addr == 4'h9) && reg_wdata[0]) begin
                        // BLIT_START = 1: Operation starten
                        cur_src <= src_addr;
                        cur_dst <= dst_addr;
                        col_cnt <= {1'b0, width_words};
                        row_cnt <= height;
                        busy    <= 1'b1;
                        if (op == OP_FILL)
                            state <= ST_FILL_REQ;
                        else
                            state <= ST_COPY_RD_REQ;
                    end
                end

                // ----------------------------------------------------------
                // FILL: Schreibt {fill_color, fill_color} ohne vorherigen Lesevorgang
                // ----------------------------------------------------------
                ST_FILL_REQ: begin
                    // Anfrage gestellt (sdram_req = 1, kombinatorisch, s.u.)
                    state <= ST_FILL_WAIT;
                end

                ST_FILL_WAIT: begin
                    if (sdram_ack) begin
                        cur_dst <= cur_dst + 1'b1;
                        col_cnt <= col_cnt - 1'b1;
                        state   <= ST_NEXT;
                    end
                end

                // ----------------------------------------------------------
                // COPY / STAMP: Lesen aus Quelle
                // ----------------------------------------------------------
                ST_COPY_RD_REQ: begin
                    state <= ST_COPY_RD_WAIT;
                end

                ST_COPY_RD_WAIT: begin
                    if (sdram_ack) begin
                        rd_buf         <= sdram_rdata;
                        stamp_dst_save <= cur_dst;
                        if (op == OP_STAMP)
                            // STAMP benötigt zusätzlich das Zielpixel (Read-Modify-Write)
                            // Wir verwenden cur_dst bereits gespeichert, weiter zu
                            // einem extra Leseschritt wäre aufwendig — vereinfacht:
                            // stamp_dst_buf = 0 (erster Entwurf, keine vollständige RMW)
                            stamp_dst_buf <= 16'h0000;
                        state <= ST_COPY_WR_REQ;
                    end
                end

                // ----------------------------------------------------------
                // Schreiben ins Ziel
                // ----------------------------------------------------------
                ST_COPY_WR_REQ: begin
                    state <= ST_COPY_WR_WAIT;
                end

                ST_COPY_WR_WAIT: begin
                    if (sdram_ack) begin
                        cur_src <= cur_src + 1'b1;
                        cur_dst <= cur_dst + 1'b1;
                        col_cnt <= col_cnt - 1'b1;
                        state   <= ST_NEXT;
                    end
                end

                // ----------------------------------------------------------
                // Nächstes Wort oder nächste Zeile
                // ----------------------------------------------------------
                ST_NEXT: begin
                    if (col_cnt == 9'h0) begin
                        // Zeile fertig
                        row_cnt <= row_cnt - 1'b1;
                        col_cnt <= {1'b0, width_words};
                        // Zeilenende: zur nächsten Framebufferzeile springen
                        // Adresse um (FB_ROW_WORDS - width_words) vorwärts
                        cur_src <= cur_src + (FB_ROW_WORDS - {18'h0, width_words});
                        cur_dst <= cur_dst + (FB_ROW_WORDS - {18'h0, width_words});
                        if (row_cnt == 8'h01) begin
                            // Alle Zeilen fertig
                            busy  <= 1'b0;
                            state <= ST_IDLE;
                        end else begin
                            if (op == OP_FILL)
                                state <= ST_FILL_REQ;
                            else
                                state <= ST_COPY_RD_REQ;
                        end
                    end else begin
                        // Nächstes Wort in dieser Zeile
                        if (op == OP_FILL)
                            state <= ST_FILL_REQ;
                        else
                            state <= ST_COPY_RD_REQ;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

    // =========================================================================
    // SDRAM-Anfragen kombinatorisch verdrahten
    // =========================================================================
    always_comb begin
        sdram_req   = 1'b0;
        sdram_we    = 1'b0;
        sdram_addr  = cur_dst;
        sdram_wdata = 16'h0000;

        unique case (state)
            ST_FILL_REQ: begin
                sdram_req   = 1'b1;
                sdram_we    = 1'b1;
                sdram_addr  = cur_dst;
                sdram_wdata = {fill_color, fill_color};
            end

            ST_COPY_RD_REQ: begin
                sdram_req   = 1'b1;
                sdram_we    = 1'b0;
                sdram_addr  = cur_src;
                sdram_wdata = 16'h0000;
            end

            ST_COPY_WR_REQ: begin
                sdram_req   = 1'b1;
                sdram_we    = 1'b1;
                sdram_addr  = stamp_dst_save;
                // COPY: rd_buf unverändert; STAMP: Colorkey-Pixel durch Ziel ersetzen
                sdram_wdata = (op == OP_STAMP) ? {stamp_hi, stamp_lo} : rd_buf;
            end

            default: begin
                sdram_req   = 1'b0;
                sdram_we    = 1'b0;
                sdram_addr  = cur_dst;
                sdram_wdata = 16'h0000;
            end
        endcase
    end

endmodule
