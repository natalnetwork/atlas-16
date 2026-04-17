// =============================================================================
// sound_chip.sv — Sound-Chip des Atlas 16
//
// Enthält:
//   - 2 Square-Wave-Kanäle (Hack-kompatibel)
//   - 4 PCM-Kanäle (Sample-Wiedergabe aus SDRAM)
//   - MIDI-Empfänger (31.250 Baud UART)
//   - Einfacher PWM-DAC-Ausgang (Sigma-Delta)
//
// Alle Kanäle werden summiert und über Sigma-Delta-PWM ausgegeben.
// Ein einfaches RC-Tiefpassfilter am GPIO-Pin erzeugt analoges Audio.
//
// Takt: 50 MHz Systemtakt
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module sound_chip (
    input  logic        clk,        // 50 MHz Systemtakt
    input  logic        rst,

    // -------------------------------------------------------------------------
    // Register-Interface (Memory-Mapped IO vom CPU-Bus)
    // -------------------------------------------------------------------------
    input  logic [7:0]  reg_addr,   // Offset zu 0x6300
    input  logic [15:0] reg_data,
    input  logic        reg_write,
    output logic [15:0] reg_read,

    // -------------------------------------------------------------------------
    // SDRAM-Interface für PCM-Samples (Kanal 2, read-only)
    // -------------------------------------------------------------------------
    output logic [26:0] sdram_addr,
    input  logic [15:0] sdram_data,
    output logic        sdram_req,
    input  logic        sdram_ack,

    // -------------------------------------------------------------------------
    // MIDI-Eingang (31.250 Baud, 8N1)
    // -------------------------------------------------------------------------
    input  logic        midi_rx,

    // -------------------------------------------------------------------------
    // Audio-Ausgabe (PWM, 1-bit)
    // An GPIO-Pin → RC-Tiefpassfilter → Lautsprecher
    // -------------------------------------------------------------------------
    output logic        audio_l,
    output logic        audio_r
);
    // =========================================================================
    // Register-Bank (intern gespiegelt für CPU-Lesezugriff)
    // =========================================================================
    logic [15:0] regs [0:63];  // 64 Register ab 0x6300

    always_ff @(posedge clk) begin
        if (rst) begin
            // Alle Register auf Standardwerte
            for (int i = 0; i < 64; i++)
                regs[i] <= 16'h0000;
        end else if (reg_write && reg_addr < 64)
            regs[reg_addr] <= reg_data;
    end

    assign reg_read = (reg_addr < 64) ? regs[reg_addr] : 16'h0000;

    // =========================================================================
    // Square-Wave-Kanal (ein Kanal)
    // Ausgabe: 1-bit, toggle wenn Zähler 0 erreicht
    // =========================================================================
    function automatic logic sq_tick;
        input logic [15:0] freq_div;
        input logic [3:0]  vol;
        // Vereinfachte Version — der echte Zähler ist weiter unten
        return (freq_div != 0) && (vol != 0);
    endfunction

    // Zähler und Phasen für Square-Wave-Kanäle 0 und 1
    logic [15:0] sq_cnt  [0:1];
    logic        sq_phase[0:1];
    logic        sq_out  [0:1];

    generate
        genvar sq_i;
        for (sq_i = 0; sq_i < 2; sq_i++) begin : sq_gen
            always_ff @(posedge clk) begin
                if (rst) begin
                    sq_cnt[sq_i]   <= 16'h0001;
                    sq_phase[sq_i] <= 1'b0;
                    sq_out[sq_i]   <= 1'b0;
                end else begin
                    // Frequenzteiler: regs[sq_i*2] = FREQ, regs[sq_i*2+1] = VOL
                    if (regs[sq_i * 2] == 0) begin
                        sq_out[sq_i] <= 1'b0; // Frequenz = 0 → stumm
                    end else begin
                        if (sq_cnt[sq_i] == 0) begin
                            sq_cnt[sq_i]   <= regs[sq_i * 2] - 1;
                            sq_phase[sq_i] <= ~sq_phase[sq_i];
                        end else begin
                            sq_cnt[sq_i] <= sq_cnt[sq_i] - 1;
                        end
                        // Lautstärke durch AND mit Phase
                        sq_out[sq_i] <= sq_phase[sq_i] &&
                                        (regs[sq_i * 2 + 1][3:0] != 4'h0);
                    end
                end
            end
        end
    endgenerate

    // =========================================================================
    // PCM-Kanal (ein Kanal, 4 identische Instanzen)
    //
    // Register-Layout pro Kanal (Offset in regs[]):
    //   +16*n+0: ADDR_LO
    //   +16*n+1: ADDR_HI
    //   +16*n+2: LEN
    //   +16*n+3: RATE (Abtastrate-Teiler)
    //   +16*n+4: VOL
    //   +16*n+5: CTRL (Bit0=play, Bit1=loop)
    // =========================================================================
    localparam int PCM_BASE = 16; // regs[16] = PCM0_ADDR_LO

    // Zustandsautomat für alle 4 PCM-Kanäle
    typedef enum logic [1:0] {
        PCM_IDLE, PCM_FETCH, PCM_PLAY, PCM_DONE
    } pcm_state_t;

    pcm_state_t  pcm_state[0:3];
    logic [26:0] pcm_addr [0:3]; // aktuelle Leseadresse
    logic [15:0] pcm_rem  [0:3]; // verbleibende Samples
    logic [15:0] pcm_rate [0:3]; // Rate-Zähler
    logic  [7:0] pcm_samp [0:3]; // aktuelles Sample
    logic        pcm_out  [0:3]; // PWM-Bit für diesen Kanal

    // Einfacher Kanal-Arbiter: immer Kanal 0 zuerst, dann 1, 2, 3
    logic [1:0] pcm_active_ch;

    always_ff @(posedge clk) begin
        if (rst) begin
            for (int i = 0; i < 4; i++) begin
                pcm_state[i] <= PCM_IDLE;
                pcm_addr[i]  <= '0;
                pcm_rem[i]   <= '0;
                pcm_rate[i]  <= 16'h0001;
            end
            pcm_active_ch <= 2'h0;
        end else begin
            // Kanal-Arbiter: reihum
            pcm_active_ch <= pcm_active_ch + 1;

            for (int ch = 0; ch < 4; ch++) begin
                logic [4:0] base;
                base = PCM_BASE + ch * 6;

                unique case (pcm_state[ch])
                    PCM_IDLE: begin
                        // Startet wenn CTRL.play gesetzt wird
                        if (regs[base + 5][0]) begin
                            pcm_addr[ch]  <= {regs[base+1][10:0], regs[base]};
                            pcm_rem[ch]   <= regs[base + 2];
                            pcm_rate[ch]  <= regs[base + 3];
                            pcm_state[ch] <= PCM_FETCH;
                        end
                    end

                    PCM_FETCH: begin
                        // SDRAM-Leseanfrage für aktiven Kanal
                        if (pcm_active_ch == ch[1:0]) begin
                            sdram_req <= 1'b1;
                            if (sdram_ack) begin
                                // High-Byte = erstes Sample, Low-Byte = zweites
                                pcm_samp[ch]  <= sdram_data[7:0];
                                pcm_addr[ch]  <= pcm_addr[ch] + 1;
                                pcm_rem[ch]   <= pcm_rem[ch] - 1;
                                pcm_state[ch] <= PCM_PLAY;
                                sdram_req     <= 1'b0;
                            end
                        end
                    end

                    PCM_PLAY: begin
                        // Sample mit Rate-Teiler ausgeben
                        if (pcm_rate[ch] == 0) begin
                            pcm_rate[ch]  <= regs[base + 3];
                            if (pcm_rem[ch] == 0) begin
                                // Sample fertig
                                if (regs[base + 5][1])  // loop?
                                    pcm_state[ch] <= PCM_IDLE; // neu starten
                                else
                                    pcm_state[ch] <= PCM_DONE;
                            end else begin
                                pcm_state[ch] <= PCM_FETCH;
                            end
                        end else begin
                            pcm_rate[ch] <= pcm_rate[ch] - 1;
                        end
                    end

                    PCM_DONE: begin
                        pcm_out[ch] <= 1'b0;
                        // CTRL.play automatisch löschen
                        regs[base + 5][0] <= 1'b0;
                        pcm_state[ch]     <= PCM_IDLE;
                    end

                    default: pcm_state[ch] <= PCM_IDLE;
                endcase
            end
        end
    end

    // SDRAM-Adresse: vom aktiven PCM-Kanal
    assign sdram_addr = pcm_addr[pcm_active_ch];

    // =========================================================================
    // MIDI-Empfänger (31.250 Baud UART, 8N1)
    // =========================================================================
    localparam int MIDI_BAUD    = 31250;
    localparam int MIDI_CLK_DIV = 50_000_000 / MIDI_BAUD; // = 1600

    typedef enum logic [1:0] { MIDI_IDLE, MIDI_START, MIDI_DATA, MIDI_STOP } midi_rx_state_t;
    midi_rx_state_t midi_state;

    logic [10:0] midi_clk_cnt;
    logic  [2:0] midi_bit_idx;
    logic  [7:0] midi_shift;
    logic  [7:0] midi_byte;
    logic        midi_ready;

    always_ff @(posedge clk) begin
        if (rst) begin
            midi_state   <= MIDI_IDLE;
            midi_ready   <= 1'b0;
        end else begin
            midi_ready <= 1'b0;

            unique case (midi_state)
                MIDI_IDLE: begin
                    if (!midi_rx) begin // Start-Bit erkannt (aktiv-niedrig)
                        midi_clk_cnt <= MIDI_CLK_DIV / 2; // Mitte des Start-Bits
                        midi_state   <= MIDI_START;
                    end
                end

                MIDI_START: begin
                    if (midi_clk_cnt == 0) begin
                        midi_clk_cnt <= MIDI_CLK_DIV - 1;
                        midi_bit_idx <= 3'h0;
                        midi_state   <= MIDI_DATA;
                    end else midi_clk_cnt <= midi_clk_cnt - 1;
                end

                MIDI_DATA: begin
                    if (midi_clk_cnt == 0) begin
                        midi_shift   <= {midi_rx, midi_shift[7:1]}; // LSB first
                        midi_clk_cnt <= MIDI_CLK_DIV - 1;
                        if (midi_bit_idx == 7)
                            midi_state <= MIDI_STOP;
                        else
                            midi_bit_idx <= midi_bit_idx + 1;
                    end else midi_clk_cnt <= midi_clk_cnt - 1;
                end

                MIDI_STOP: begin
                    if (midi_clk_cnt == 0) begin
                        midi_byte  <= midi_shift;
                        midi_ready <= 1'b1;
                        midi_state <= MIDI_IDLE;
                        // Byte in MIDI_RX-Register (regs[0x30 - 0x00 = 48])
                        regs[48]       <= {8'h00, midi_shift};
                        regs[49][0]    <= 1'b1; // RX_READY setzen
                    end else midi_clk_cnt <= midi_clk_cnt - 1;
                end

                default: midi_state <= MIDI_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Mischer: alle Kanäle summieren
    // 2 Square-Wave + 4 PCM → 6 Kanäle → 4-bit Summenwert → Sigma-Delta
    // =========================================================================
    logic [3:0] mix_sum;

    always_comb begin
        mix_sum = 4'h0;
        // Square Wave Kanäle: vol-gewichtet
        for (int i = 0; i < 2; i++) begin
            if (sq_out[i])
                mix_sum = mix_sum + {1'b0, regs[i*2+1][2:0]};
        end
        // PCM-Kanäle: vereinfacht 1-bit PWM
        for (int i = 0; i < 4; i++) begin
            if (pcm_out[i])
                mix_sum = mix_sum + 4'h1;
        end
    end

    // =========================================================================
    // Sigma-Delta-DAC (1-bit Ausgabe)
    // Wandelt den 4-bit Summenwert in ein 1-bit PWM-Signal um.
    // Ein RC-Tiefpassfilter (z.B. 1kΩ + 10nF) am GPIO-Pin glättet das Signal.
    // =========================================================================
    logic [4:0] sigma_delta_acc;

    always_ff @(posedge clk) begin
        if (rst) begin
            sigma_delta_acc <= 5'h00;
            audio_l         <= 1'b0;
            audio_r         <= 1'b0;
        end else begin
            sigma_delta_acc <= sigma_delta_acc[3:0] + {1'b0, mix_sum};
            audio_l         <= sigma_delta_acc[4];
            audio_r         <= sigma_delta_acc[4];
        end
    end

endmodule
