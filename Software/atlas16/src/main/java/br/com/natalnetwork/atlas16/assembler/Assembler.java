package br.com.natalnetwork.atlas16.assembler;

import br.com.natalnetwork.atlas16.common.AssemblerException;

import java.io.*;
import java.nio.file.*;
import java.util.*;

public class Assembler {

    // C-Instruktions-Tabellen (gemäß [N2T] Anhang A)
    private static final Map<String, String> COMP = new HashMap<>();
    private static final Map<String, String> DEST = new HashMap<>();
    private static final Map<String, String> JUMP = new HashMap<>();

    static {
        // a=0
        COMP.put("0",   "0101010"); COMP.put("1",   "0111111");
        COMP.put("-1",  "0111010"); COMP.put("D",   "0001100");
        COMP.put("A",   "0110000"); COMP.put("!D",  "0001101");
        COMP.put("!A",  "0110001"); COMP.put("-D",  "0001111");
        COMP.put("-A",  "0110011"); COMP.put("D+1", "0011111");
        COMP.put("A+1", "0110111"); COMP.put("D-1", "0001110");
        COMP.put("A-1", "0110010"); COMP.put("D+A", "0000010");
        COMP.put("D-A", "0010011"); COMP.put("A-D", "0000111");
        COMP.put("D&A", "0000000"); COMP.put("D|A", "0010101");
        // a=1
        COMP.put("M",   "1110000"); COMP.put("!M",  "1110001");
        COMP.put("-M",  "1110011"); COMP.put("M+1", "1110111");
        COMP.put("M-1", "1110010"); COMP.put("D+M", "1000010");
        COMP.put("D-M", "1010011"); COMP.put("M-D", "1000111");
        COMP.put("D&M", "1000000"); COMP.put("D|M", "1010101");

        DEST.put("",    "000"); DEST.put("M",   "001");
        DEST.put("D",   "010"); DEST.put("MD",  "011");
        DEST.put("A",   "100"); DEST.put("AM",  "101");
        DEST.put("AD",  "110"); DEST.put("AMD", "111");

        JUMP.put("",    "000"); JUMP.put("JGT", "001");
        JUMP.put("JEQ", "010"); JUMP.put("JGE", "011");
        JUMP.put("JLT", "100"); JUMP.put("JNE", "101");
        JUMP.put("JLE", "110"); JUMP.put("JMP", "111");
    }

    private final List<String> sourceLines;

    public Assembler(List<String> sourceLines) {
        this.sourceLines = sourceLines;
    }

    public static Assembler fromFile(Path path) throws IOException {
        return new Assembler(Files.readAllLines(path));
    }

    public List<String> assemble() {
        Map<String, Integer> symbols = firstPass();
        return secondPass(symbols);
    }

    // Erster Durchlauf: Labels sammeln
    private Map<String, Integer> firstPass() {
        Map<String, Integer> symbols = new HashMap<>(Symbols.predefined());
        int instrCount = 0;
        for (String raw : sourceLines) {
            String line = stripLine(raw);
            if (line.isEmpty()) continue;
            if (line.startsWith("(") && line.endsWith(")")) {
                String label = line.substring(1, line.length() - 1);
                if (symbols.containsKey(label))
                    throw new AssemblerException("Label '" + label + "' bereits definiert.");
                symbols.put(label, instrCount);
            } else {
                instrCount++;
            }
        }
        return symbols;
    }

    // Zweiter Durchlauf: übersetzen
    private List<String> secondPass(Map<String, Integer> symbols) {
        List<String> output = new ArrayList<>();
        int nextVar = 16;
        int lineno = 0;

        for (String raw : sourceLines) {
            lineno++;
            String line = stripLine(raw);
            if (line.isEmpty() || (line.startsWith("(") && line.endsWith(")"))) continue;

            if (line.startsWith("@")) {
                String sym = line.substring(1);
                int value;
                try {
                    value = Integer.parseInt(sym);
                    if (value < 0 || value > 32767)
                        throw new AssemblerException(lineno, "Wert " + value + " außerhalb 0–32767.");
                } catch (NumberFormatException e) {
                    if (symbols.containsKey(sym)) {
                        value = symbols.get(sym);
                    } else {
                        symbols.put(sym, nextVar);
                        value = nextVar++;
                    }
                }
                output.add(toBin16(value));
            } else {
                // C-Instruktion: dest=comp;jump
                String dest = "", comp = line, jump = "";
                int eq = comp.indexOf('=');
                if (eq >= 0) { dest = comp.substring(0, eq); comp = comp.substring(eq + 1); }
                int sc = comp.indexOf(';');
                if (sc >= 0) { jump = comp.substring(sc + 1); comp = comp.substring(0, sc); }

                dest = dest.strip(); comp = comp.strip(); jump = jump.strip();

                if (!COMP.containsKey(comp))
                    throw new AssemblerException(lineno, "Unbekannter comp-Wert '" + comp + "'.");
                if (!DEST.containsKey(dest))
                    throw new AssemblerException(lineno, "Unbekannter dest-Wert '" + dest + "'.");
                if (!JUMP.containsKey(jump))
                    throw new AssemblerException(lineno, "Unbekannter jump-Wert '" + jump + "'.");

                output.add("111" + COMP.get(comp) + DEST.get(dest) + JUMP.get(jump));
            }
        }
        return output;
    }

    private static String stripLine(String line) {
        int idx = line.indexOf("//");
        if (idx >= 0) line = line.substring(0, idx);
        return line.strip();
    }

    private static String toBin16(int value) {
        if (value < 0) value &= 0xFFFF;
        return String.format("%16s", Integer.toBinaryString(value)).replace(' ', '0');
    }
}
