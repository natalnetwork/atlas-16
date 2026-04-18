package br.com.natalnetwork.atlas16.assembler;

import java.util.HashMap;
import java.util.Map;

public final class Symbols {

    private Symbols() {}

    public static Map<String, Integer> predefined() {
        Map<String, Integer> t = new HashMap<>();

        // N2T Standard-Register
        for (int i = 0; i <= 15; i++) t.put("R" + i, i);

        // N2T VM-Zeiger
        t.put("SP",   0); t.put("LCL",  1); t.put("ARG",  2);
        t.put("THIS", 3); t.put("THAT", 4);

        // N2T Legacy I/O
        t.put("SCREEN", 0x4000);
        t.put("KBD",    0x6000);

        // VGA
        t.put("VGA_MODE",       0x6001);
        t.put("VGA_FB_BASE_LO", 0x6002);
        t.put("VGA_FB_BASE_HI", 0x6003);
        t.put("PALETTE_0",      0x6004);
        t.put("PALETTE_1",      0x6005);

        // Sprites
        t.put("SPRITE_0_X",      0x6100); t.put("SPRITE_0_Y",      0x6101);
        t.put("SPRITE_0_ADDR_L", 0x6102); t.put("SPRITE_0_ADDR_H", 0x6103);
        t.put("SPRITE_0_FLAGS",  0x6104); t.put("SPRITE_0_CKEY",   0x6105);
        t.put("SPRITE_1_X",      0x6108); t.put("SPRITE_1_Y",      0x6109);
        t.put("SPRITE_1_ADDR_L", 0x610A); t.put("SPRITE_1_ADDR_H", 0x610B);
        t.put("SPRITE_1_FLAGS",  0x610C); t.put("SPRITE_1_CKEY",   0x610D);

        // Blitter
        t.put("BLIT_SRC_LO",  0x6200); t.put("BLIT_SRC_HI",  0x6201);
        t.put("BLIT_DST_LO",  0x6202); t.put("BLIT_DST_HI",  0x6203);
        t.put("BLIT_WIDTH",   0x6204); t.put("BLIT_HEIGHT",   0x6205);
        t.put("BLIT_COLOR",   0x6206); t.put("BLIT_COLORKEY", 0x6207);
        t.put("BLIT_OP",      0x6208); t.put("BLIT_START",    0x6209);
        t.put("BLIT_BUSY",    0x620A);

        // Sound
        t.put("SQ0_FREQ",     0x6300); t.put("SQ0_VOL",      0x6301);
        t.put("SQ1_FREQ",     0x6302); t.put("SQ1_VOL",      0x6303);
        t.put("PCM0_ADDR_LO", 0x6310); t.put("PCM0_ADDR_HI", 0x6311);
        t.put("PCM0_LEN",     0x6312); t.put("PCM0_RATE",    0x6313);
        t.put("PCM0_VOL",     0x6314); t.put("PCM0_CTRL",    0x6315);
        t.put("PCM1_ADDR_LO", 0x6316); t.put("PCM1_ADDR_HI", 0x6317);
        t.put("PCM1_LEN",     0x6318); t.put("PCM1_RATE",    0x6319);
        t.put("PCM1_VOL",     0x631A); t.put("PCM1_CTRL",    0x631B);
        t.put("MIDI_RX",      0x6330); t.put("MIDI_STATUS",  0x6331);

        // UART
        t.put("UART_DATA",   0x6400); t.put("UART_STATUS", 0x6401);

        // RTC
        t.put("RTC_SEC",  0x6410); t.put("RTC_MIN",  0x6411);
        t.put("RTC_HOUR", 0x6412); t.put("RTC_DAY",  0x6413);
        t.put("RTC_MON",  0x6414); t.put("RTC_YEAR", 0x6415);

        // Timer
        t.put("TMR_CNT",    0x6420); t.put("TMR_RELOAD", 0x6421);
        t.put("TMR_CTRL",   0x6422); t.put("TMR_STATUS", 0x6423);

        // Bank-Controller
        t.put("BANK_CTRL", 0x6430);

        // Eingabegeräte
        t.put("MOUSE_X",   0x6440); t.put("MOUSE_Y",   0x6441);
        t.put("MOUSE_BTN", 0x6442);
        t.put("PAD_BTN",   0x6460); t.put("PAD_LEFT",  0x6461);
        t.put("PAD_RIGHT", 0x6462); t.put("PAD_TRG",   0x6463);

        // Gamepad-Button-Masken
        t.put("PAD_A",    1);    t.put("PAD_B",    2);
        t.put("PAD_X",    4);    t.put("PAD_Y",    8);
        t.put("PAD_LB",   16);   t.put("PAD_RB",   32);
        t.put("PAD_START",64);   t.put("PAD_BACK", 128);
        t.put("PAD_DPAD_UP",    256);  t.put("PAD_DPAD_DOWN",  512);
        t.put("PAD_DPAD_LEFT", 1024);  t.put("PAD_DPAD_RIGHT", 2048);
        t.put("PAD_CONNECTED", 32768);

        return t;
    }
}
