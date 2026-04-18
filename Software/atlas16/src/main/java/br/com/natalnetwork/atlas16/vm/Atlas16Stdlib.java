package br.com.natalnetwork.atlas16.vm;

public final class Atlas16Stdlib {

    private Atlas16Stdlib() {}

    public static final String CODE = """
// ─────────────────────────────────────────────────────────────────────────────
// Atlas16 Standard-Library (inline, generiert von atlas16.jar vm)
// ─────────────────────────────────────────────────────────────────────────────
// Atlas16.screenMode(mode): VGA_MODE ← ARG[0]
(Atlas16.screenMode)
    @ARG
    A=M
    D=M
    @VGA_MODE
    M=D
    @SP
    AM=M-1
    D=M
    @ARG
    A=M
    M=D
    @LCL
    A=M-1
    D=M
    @R14
    M=D
    @SP
    M=M+1
    @R14
    A=M
    0;JMP

// Atlas16.screenPoke(x, y, c): Pixel bei (x,y) mit Farbe c setzen (8bpp)
(Atlas16.screenPoke)
    @ARG
    D=M
    @2
    A=D+A
    D=M
    @R13
    M=D
    @ARG
    D=M
    @1
    A=D+A
    D=M
    @R14
    M=D
    M=M+M
    M=M+M
    M=M+M
    M=M+M
    M=M+M
    M=M+M
    M=M+M
    M=M+M
    M=M+M
    @ARG
    D=M
    A=D
    D=M
    @R14
    M=M+D
    @VGA_FB_BASE_LO
    D=M
    @R14
    M=M+D
    @R13
    D=M
    @R14
    A=M
    M=D
    @0
    D=A
    @SP
    A=M
    M=D
    @SP
    M=M+1
    @Atlas16.screenPoke$ret
    0;JMP
(Atlas16.screenPoke$ret)

// Atlas16.readKey(): D = KBD (0x6000)
(Atlas16.readKey)
    @KBD
    D=M
    @SP
    A=M
    M=D
    @SP
    M=M+1
    @Atlas16.readKey$ret
    0;JMP
(Atlas16.readKey$ret)

// Atlas16.readPad(): D = PAD_BTN (0x6460)
(Atlas16.readPad)
    @PAD_BTN
    D=M
    @SP
    A=M
    M=D
    @SP
    M=M+1
    @Atlas16.readPad$ret
    0;JMP
(Atlas16.readPad$ret)

// Atlas16.soundTone(ch, freq, vol)
(Atlas16.soundTone)
    @ARG
    D=M
    A=D
    D=M
    @Atlas16.soundTone$ch1
    D;JNE
    @ARG
    D=M
    @1
    A=D+A
    D=M
    @SQ0_FREQ
    M=D
    @ARG
    D=M
    @2
    A=D+A
    D=M
    @SQ0_VOL
    M=D
    @Atlas16.soundTone$end
    0;JMP
(Atlas16.soundTone$ch1)
    @ARG
    D=M
    @1
    A=D+A
    D=M
    @SQ1_FREQ
    M=D
    @ARG
    D=M
    @2
    A=D+A
    D=M
    @SQ1_VOL
    M=D
(Atlas16.soundTone$end)
    @0
    D=A
    @SP
    A=M
    M=D
    @SP
    M=M+1
    @Atlas16.soundTone$ret
    0;JMP
(Atlas16.soundTone$ret)
""";
}
