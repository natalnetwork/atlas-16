// =============================================================================
// atlas16_top.sv — Toplevel des Atlas 16 FPGA-Computers
//
// Verdrahtet alle Komponenten:
//   - Hack+ CPU
//   - Instruction ROM (BRAM)
//   - Data RAM (BRAM)
//   - Peripherie-Decoder (Memory-Mapped IO)
//   - VGA/HDMI-Controller
//   - Sound-Chip
//   - UART
//   - RTC
//   - Timer
//   - HPS-Mailbox
//   - SDRAM-Controller (Platzhalter — wird in Milestone 2 ergänzt)
//
// Pin-Assignments: Terasic DE10-Nano
//   50 MHz Takt:   PIN_V11
//   HDMI:          ADV7513 (I2C-Konfiguration durch Angstrom-OS beim Boot)
//   Audio:         GPIO_0[0]/GPIO_0[1] (PWM → RC-Filter)
//   UART TX/RX:    GPIO_1[0]/GPIO_1[1]
//   MIDI RX:       GPIO_1[2]
//   SDRAM:         GPIO_0 Header (MiSTer XSD 2.5)
//
// Autor:  Sebastian Schwiebert
// Lizenz: MIT
// HDL:    SystemVerilog IEEE 1800-2005
// =============================================================================
module atlas16_top (
    // -------------------------------------------------------------------------
    // DE10-Nano Basistakte und Reset
    // -------------------------------------------------------------------------
    input  logic        CLOCK_50,       // 50 MHz Systemtakt
    input  logic  [1:0] KEY,            // KEY[0] = Reset (aktiv-niedrig)

    // -------------------------------------------------------------------------
    // HDMI-Ausgabe (an ADV7513)
    // -------------------------------------------------------------------------
    output logic        HDMI_TX_CLK,
    output logic        HDMI_TX_DE,
    output logic        HDMI_TX_HS,
    output logic        HDMI_TX_VS,
    output logic [23:0] HDMI_TX_D,      // RGB 8-8-8

    // -------------------------------------------------------------------------
    // GPIO-Ausgaben
    // -------------------------------------------------------------------------
    output logic  [1:0] GPIO_0_AUDIO,   // [0]=Audio L, [1]=Audio R
    output logic        GPIO_1_UART_TX,
    input  logic        GPIO_1_UART_RX,
    input  logic        GPIO_1_MIDI_RX,

    // -------------------------------------------------------------------------
    // SDRAM (MiSTer XSD 2.5, GPIO0 Header)
    // -------------------------------------------------------------------------
    output logic [12:0] SDRAM_A,
    inout  logic [15:0] SDRAM_DQ,
    output logic  [1:0] SDRAM_BA,
    output logic        SDRAM_CAS_N,
    output logic        SDRAM_RAS_N,
    output logic        SDRAM_WE_N,
    output logic        SDRAM_CS_N,
    output logic        SDRAM_CKE,
    output logic        SDRAM_CLK,
    output logic  [1:0] SDRAM_DQM,

    // -------------------------------------------------------------------------
    // HPS-to-FPGA Lightweight Bridge (Avalon-MM Slave)
    // 5-bit Wortadresse = 32 Register × 4 Byte = 128 Byte Adressraum
    // -------------------------------------------------------------------------
    input  logic  [4:0] HPS_LW_ADDR,
    input  logic [31:0] HPS_LW_WDATA,
    input  logic        HPS_LW_WRITE,
    input  logic        HPS_LW_READ,
    output logic [31:0] HPS_LW_RDATA
);
    // =========================================================================
    // Globale Signale
    // =========================================================================
    logic clk;          // 50 MHz Systemtakt
    logic clk_25mhz;    // 25 MHz für VGA-Pixeltakt
    logic rst;          // synchroner Reset (aktiv-hoch)

    assign clk = CLOCK_50;
    assign rst = ~KEY[0]; // KEY[0] gedrückt (low) = Reset

    // VGA-Pixeltakt: 50 MHz / 2 = 25 MHz (vereinfacht)
    // Für genaues 25,175 MHz: PLL verwenden (in Quartus konfigurieren)
    logic clk_div2;
    always_ff @(posedge clk) clk_div2 <= ~clk_div2;
    assign clk_25mhz = clk_div2;

    // =========================================================================
    // CPU ↔ Memory Interface
    // =========================================================================
    logic [14:0] cpu_pc;
    logic [15:0] cpu_instruction;
    logic [15:0] cpu_mem_addr;
    logic [15:0] cpu_mem_out;
    logic        cpu_mem_write;
    logic [15:0] cpu_mem_in;
    logic        cpu_rst_combined;

    // =========================================================================
    // HPS Mailbox → CPU Reset/Halt + Eingabegeräte
    // =========================================================================
    logic hps_cpu_rst, hps_cpu_halt;
    logic [14:0] hps_rom_addr;
    logic [15:0] hps_rom_data;
    logic        hps_rom_wr_en;
    logic  [7:0] hps_rtc_sec, hps_rtc_min, hps_rtc_hour;
    logic        hps_rtc_update;
    // Eingabegeräte (aus Mailbox → CPU-MMIO)
    logic [15:0] hps_kbd_key;
    logic [15:0] hps_mouse_x, hps_mouse_y, hps_mouse_btn;
    logic [15:0] hps_pad_btn, hps_pad_left, hps_pad_right, hps_pad_trg;

    assign cpu_rst_combined = rst | hps_cpu_rst | hps_cpu_halt;

    // =========================================================================
    // Hack-CPU instanziieren
    // =========================================================================
    hack_cpu cpu_inst (
        .clk         (clk),
        .rst         (cpu_rst_combined),
        .instruction (cpu_instruction),
        .mem_in      (cpu_mem_in),
        .mem_out     (cpu_mem_out),
        .mem_addr    (cpu_mem_addr),
        .mem_write   (cpu_mem_write),
        .pc          (cpu_pc)
    );

    // =========================================================================
    // Instruction ROM instanziieren
    // =========================================================================
    hack_rom rom_inst (
        .clk         (clk),
        .pc          (cpu_pc),
        .instruction (cpu_instruction),
        .wr_addr     (hps_rom_addr),
        .wr_data     (hps_rom_data),
        .wr_en       (hps_rom_wr_en)
    );

    // =========================================================================
    // Peripherie-Decoder (Memory-Mapped IO)
    // Leitet CPU-Zugriffe auf die richtige Komponente weiter
    // =========================================================================
    logic [15:0] per_rd_data;   // Lesedaten vom jeweils adressierten Gerät

    // Adress-Dekodierung
    logic sel_vga, sel_sprites, sel_blitter, sel_sound;
    logic sel_uart, sel_rtc, sel_timer, sel_bank, sel_mailbox;
    logic sel_mouse, sel_pad;

    assign sel_vga      = (cpu_mem_addr >= 16'h6001) && (cpu_mem_addr <= 16'h600F);
    assign sel_sprites  = (cpu_mem_addr >= 16'h6100) && (cpu_mem_addr <= 16'h617F);
    assign sel_blitter  = (cpu_mem_addr >= 16'h6200) && (cpu_mem_addr <= 16'h620A);
    assign sel_sound    = (cpu_mem_addr >= 16'h6300) && (cpu_mem_addr <= 16'h6331);
    assign sel_uart     = (cpu_mem_addr >= 16'h6400) && (cpu_mem_addr <= 16'h6401);
    assign sel_rtc      = (cpu_mem_addr >= 16'h6410) && (cpu_mem_addr <= 16'h6415);
    assign sel_timer    = (cpu_mem_addr >= 16'h6420) && (cpu_mem_addr <= 16'h6423);
    assign sel_bank     = (cpu_mem_addr == 16'h6430);
    assign sel_mouse    = (cpu_mem_addr >= 16'h6440) && (cpu_mem_addr <= 16'h6442);
    assign sel_mailbox  = (cpu_mem_addr >= 16'h6450) && (cpu_mem_addr <= 16'h6457);
    assign sel_pad      = (cpu_mem_addr >= 16'h6460) && (cpu_mem_addr <= 16'h6463);

    // =========================================================================
    // VGA-Konfigurationsregister
    // =========================================================================
    logic        vga_mode;
    logic [26:0] vga_fb_base;
    logic  [7:0] vga_palette_0, vga_palette_1;

    always_ff @(posedge clk) begin
        if (rst) begin
            vga_mode      <= 1'b0;
            vga_fb_base   <= 27'h0;
            vga_palette_0 <= 8'h00;
            vga_palette_1 <= 8'hFF;
        end else if (cpu_mem_write && sel_vga) begin
            unique case (cpu_mem_addr)
                16'h6001: vga_mode      <= cpu_mem_out[0];
                16'h6002: vga_fb_base[15:0]  <= cpu_mem_out;
                16'h6003: vga_fb_base[26:16] <= cpu_mem_out[10:0];
                16'h6004: vga_palette_0 <= cpu_mem_out[7:0];
                16'h6005: vga_palette_1 <= cpu_mem_out[7:0];
                default: ;
            endcase
        end
    end

    // =========================================================================
    // UART instanziieren
    // =========================================================================
    logic [7:0] uart_rd;
    logic       uart_tx_wire;

    uart uart_inst (
        .clk       (clk),
        .rst       (rst),
        .rx        (GPIO_1_UART_RX),
        .tx        (uart_tx_wire),
        .reg_addr  (cpu_mem_addr[0]),
        .reg_wdata (cpu_mem_out[7:0]),
        .reg_write (cpu_mem_write && sel_uart),
        .reg_rdata (uart_rd)
    );

    assign GPIO_1_UART_TX = uart_tx_wire;

    // =========================================================================
    // RTC instanziieren
    // =========================================================================
    logic [15:0] rtc_rd;

    rtc rtc_inst (
        .clk       (clk),
        .rst       (rst),
        .reg_addr  (cpu_mem_addr[2:0]),
        .reg_rdata (rtc_rd),
        .upd_sec   (hps_rtc_sec),
        .upd_min   (hps_rtc_min),
        .upd_hour  (hps_rtc_hour),
        .upd_en    (hps_rtc_update)
    );

    // =========================================================================
    // Timer instanziieren
    // =========================================================================
    logic [15:0] tmr_rd;

    timer timer_inst (
        .clk       (clk),
        .rst       (rst),
        .reg_addr  (cpu_mem_addr[1:0]),
        .reg_wdata (cpu_mem_out),
        .reg_write (cpu_mem_write && sel_timer),
        .reg_rdata (tmr_rd)
    );

    // =========================================================================
    // HPS-Mailbox instanziieren
    // =========================================================================
    hps_mailbox mailbox_inst (
        .clk        (clk),
        .rst        (rst),
        .hps_addr   (HPS_LW_ADDR),
        .hps_wdata  (HPS_LW_WDATA),
        .hps_write  (HPS_LW_WRITE),
        .hps_read   (HPS_LW_READ),
        .hps_rdata  (HPS_LW_RDATA),
        .cpu_rst    (hps_cpu_rst),
        .cpu_halt   (hps_cpu_halt),
        .rom_wr_addr(hps_rom_addr),
        .rom_wr_data(hps_rom_data),
        .rom_wr_en  (hps_rom_wr_en),
        .rtc_sec    (hps_rtc_sec),
        .rtc_min    (hps_rtc_min),
        .rtc_hour   (hps_rtc_hour),
        .rtc_update (hps_rtc_update),
        .kbd_key    (hps_kbd_key),
        .mouse_x    (hps_mouse_x),
        .mouse_y    (hps_mouse_y),
        .mouse_btn  (hps_mouse_btn),
        .pad_btn    (hps_pad_btn),
        .pad_left   (hps_pad_left),
        .pad_right  (hps_pad_right),
        .pad_trg    (hps_pad_trg),
        .cmd_done   (1'b1)  // vereinfacht: sofort quittieren
    );

    // =========================================================================
    // Sound-Chip instanziieren
    // =========================================================================
    logic [15:0] snd_rd;
    // SDRAM-Kanal 2 (Platzhalter bis SDRAM implementiert)
    logic [26:0] snd_sdram_addr;
    logic        snd_sdram_req;

    sound_chip snd_inst (
        .clk       (clk),
        .rst       (rst),
        .reg_addr  (cpu_mem_addr[5:0]),
        .reg_data  (cpu_mem_out),
        .reg_write (cpu_mem_write && sel_sound),
        .reg_read  (snd_rd),
        .sdram_addr(snd_sdram_addr),
        .sdram_data(16'h0),     // Platzhalter
        .sdram_req (snd_sdram_req),
        .sdram_ack (1'b0),      // Platzhalter
        .midi_rx   (GPIO_1_MIDI_RX),
        .audio_l   (GPIO_0_AUDIO[0]),
        .audio_r   (GPIO_0_AUDIO[1])
    );

    // =========================================================================
    // VGA-Controller instanziieren
    // =========================================================================
    logic [26:0] vga_sdram_addr;
    logic [15:0] vga_sdram_data;
    logic        vga_sdram_req, vga_sdram_ack;

    // Timing- und Compositing-Signale zwischen VGA-Controller und Sprite Engine
    logic  [9:0] vga_hcount, vga_vcount;
    logic  [7:0] sprite_pixel_out;
    logic        sprite_valid_out;

    vga_controller vga_inst (
        .clk_25mhz   (clk_25mhz),
        .rst         (rst),
        .vga_mode    (vga_mode),
        .fb_base     (vga_fb_base),
        .palette_0   (vga_palette_0),
        .palette_1   (vga_palette_1),
        .sdram_addr  (vga_sdram_addr),
        .sdram_data  (vga_sdram_data),
        .sdram_req   (vga_sdram_req),
        .sdram_ack   (vga_sdram_ack),
        .hsync       (HDMI_TX_HS),
        .vsync       (HDMI_TX_VS),
        .de          (HDMI_TX_DE),
        .r           (HDMI_TX_D[23:16]),
        .g           (HDMI_TX_D[15:8]),
        .b           (HDMI_TX_D[7:0]),
        .hcount      (vga_hcount),
        .vcount      (vga_vcount),
        .sprite_pixel(sprite_pixel_out),
        .sprite_valid(sprite_valid_out)
    );

    assign HDMI_TX_CLK = clk_25mhz;

    // =========================================================================
    // Sprite Engine instanziieren
    // =========================================================================
    sprite_engine spr_inst (
        .clk         (clk),
        .rst         (rst),
        .reg_addr    (cpu_mem_addr[6:0]),
        .reg_wdata   (cpu_mem_out),
        .reg_write   (cpu_mem_write && sel_sprites),
        .hcount      (vga_hcount),
        .vcount      (vga_vcount),
        .sdram_addr  (),            // Platzhalter (SDRAM Milestone 2)
        .sdram_data  (16'h0),
        .sdram_req   (),
        .sdram_ack   (1'b0),
        .sprite_pixel(sprite_pixel_out),
        .sprite_valid(sprite_valid_out)
    );

    // =========================================================================
    // Blitter instanziieren
    // =========================================================================
    logic [15:0] blit_rd;

    blitter blit_inst (
        .clk        (clk),
        .rst        (rst),
        .reg_addr   (cpu_mem_addr[3:0]),
        .reg_wdata  (cpu_mem_out),
        .reg_write  (cpu_mem_write && sel_blitter),
        .reg_rdata  (blit_rd),
        .sdram_addr (),             // Platzhalter (SDRAM Milestone 2)
        .sdram_we   (),
        .sdram_wdata(),
        .sdram_rdata(16'h0),
        .sdram_req  (),
        .sdram_ack  (1'b0)
    );

    // =========================================================================
    // Data RAM instanziieren
    // =========================================================================
    logic [12:0] fb_wr_addr;
    logic [15:0] fb_wr_data;
    logic        fb_wr_en;
    logic [15:0] per_rd_mux;

    // Peripherie-Lesemultiplexer
    always_comb begin
        per_rd_mux = 16'h0000;
        if (sel_uart)    per_rd_mux = {8'h0, uart_rd};
        if (sel_rtc)     per_rd_mux = rtc_rd;
        if (sel_timer)   per_rd_mux = tmr_rd;
        if (sel_sound)   per_rd_mux = snd_rd;
        if (sel_blitter) per_rd_mux = blit_rd;
        // Maus-Register (read-only für CPU)
        if (sel_mouse) begin
            unique case (cpu_mem_addr)
                16'h6440: per_rd_mux = hps_mouse_x;
                16'h6441: per_rd_mux = hps_mouse_y;
                16'h6442: per_rd_mux = hps_mouse_btn;
                default:  per_rd_mux = 16'h0000;
            endcase
        end
        // Gamepad-Register (read-only für CPU)
        if (sel_pad) begin
            unique case (cpu_mem_addr)
                16'h6460: per_rd_mux = hps_pad_btn;
                16'h6461: per_rd_mux = hps_pad_left;
                16'h6462: per_rd_mux = hps_pad_right;
                16'h6463: per_rd_mux = hps_pad_trg;
                default:  per_rd_mux = 16'h0000;
            endcase
        end
    end

    hack_ram ram_inst (
        .clk       (clk),
        .rst       (rst),
        .address   (cpu_mem_addr),
        .data_in   (cpu_mem_out),
        .write_en  (cpu_mem_write),
        .data_out  (cpu_mem_in),
        .keyboard_in(hps_kbd_key),  // ASCII-Code der aktuellen Taste (0x6000)
        .fb_addr   (fb_wr_addr),
        .fb_data   (fb_wr_data),
        .fb_write  (fb_wr_en),
        .per_addr  (),
        .per_data  (),
        .per_write (),
        .per_read  (per_rd_mux)
    );

    // =========================================================================
    // SDRAM (Platzhalter für Milestone 2)
    // Im Milestone 1 läuft alles aus BRAM
    // =========================================================================
    assign SDRAM_A      = '0;
    assign SDRAM_BA     = '0;
    assign SDRAM_CAS_N  = 1'b1;
    assign SDRAM_RAS_N  = 1'b1;
    assign SDRAM_WE_N   = 1'b1;
    assign SDRAM_CS_N   = 1'b1;
    assign SDRAM_CKE    = 1'b0;
    assign SDRAM_CLK    = 1'b0;
    assign SDRAM_DQM    = 2'b11;
    assign vga_sdram_data = 16'h0;
    assign vga_sdram_ack  = 1'b0;

endmodule
