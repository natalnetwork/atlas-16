package br.com.natalnetwork.atlas16.common;

public class AssemblerException extends RuntimeException {
    private final int line;

    public AssemblerException(int line, String message) {
        super(line > 0 ? "Zeile " + line + ": " + message : message);
        this.line = line;
    }

    public AssemblerException(String message) {
        this(0, message);
    }

    public int getLine() { return line; }
}
