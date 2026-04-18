package br.com.natalnetwork.atlas16;

import br.com.natalnetwork.atlas16.assembler.Assembler;
import br.com.natalnetwork.atlas16.common.AssemblerException;
import br.com.natalnetwork.atlas16.jack.JackCompiler;
import br.com.natalnetwork.atlas16.loader.HpsLoader;
import br.com.natalnetwork.atlas16.vm.VmTranslator;

import java.io.*;
import java.nio.file.*;
import java.util.*;

/**
 * Atlas 16 Toolchain — Einstiegspunkt
 *
 * Verwendung:
 *   java -jar atlas16.jar asm   <datei.asm>  [-o out.hack] [--bin]
 *   java -jar atlas16.jar vm    <datei.vm|dir> [-o out.asm] [--no-bootstrap]
 *   java -jar atlas16.jar load  <datei.hack> --ip <ip> [--user <user>]
 */
public class Main {

    public static void main(String[] args) {
        if (args.length == 0) { printHelp(); System.exit(1); }

        try {
            switch (args[0]) {
                case "asm"   -> runAsm(Arrays.copyOfRange(args, 1, args.length));
                case "vm"    -> runVm(Arrays.copyOfRange(args, 1, args.length));
                case "jack"  -> runJack(Arrays.copyOfRange(args, 1, args.length));
                case "build" -> runBuild(Arrays.copyOfRange(args, 1, args.length));
                case "load"  -> runLoad(Arrays.copyOfRange(args, 1, args.length));
                default      -> { System.err.println("Unbekannter Befehl: " + args[0]); printHelp(); System.exit(1); }
            }
        } catch (AssemblerException e) {
            System.err.println("Fehler: " + e.getMessage());
            System.exit(1);
        } catch (Exception e) {
            System.err.println("Fehler: " + e.getMessage());
            System.exit(1);
        }
    }

    // ── asm ──────────────────────────────────────────────────────────────────

    private static void runAsm(String[] args) throws Exception {
        String source = null, output = null;
        boolean binary = false;

        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "-o", "--output" -> output = args[++i];
                case "--bin"          -> binary = true;
                default -> { if (source == null) source = args[i]; }
            }
        }
        if (source == null) { System.err.println("Verwendung: asm <datei.asm> [-o out.hack] [--bin]"); System.exit(1); }

        Path srcPath = Path.of(source);
        Path outPath = output != null ? Path.of(output)
                                      : srcPath.resolveSibling(baseName(srcPath) + ".hack");

        Assembler asm = Assembler.fromFile(srcPath);
        List<String> instructions = asm.assemble();

        Files.writeString(outPath, String.join("\n", instructions) + "\n");
        System.out.println("[asm] " + instructions.size() + " Instruktionen → " + outPath);

        if (binary) {
            Path binPath = outPath.resolveSibling(baseName(outPath) + ".bin");
            try (OutputStream os = Files.newOutputStream(binPath)) {
                for (String word : instructions) {
                    int v = Integer.parseInt(word, 2);
                    os.write((v >> 8) & 0xFF);
                    os.write(v & 0xFF);
                }
            }
            System.out.println("[asm] Binärdatei → " + binPath);
        }
    }

    // ── vm ───────────────────────────────────────────────────────────────────

    private static void runVm(String[] args) throws Exception {
        String source = null, output = null;
        boolean bootstrap = true;

        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "-o", "--output"    -> output = args[++i];
                case "--no-bootstrap"    -> bootstrap = false;
                default -> { if (source == null) source = args[i]; }
            }
        }
        if (source == null) { System.err.println("Verwendung: vm <datei.vm|dir> [-o out.asm] [--no-bootstrap]"); System.exit(1); }

        Path input = Path.of(source);
        List<Path> sources = VmTranslator.collectSources(input);

        Path outPath;
        if (output != null) {
            outPath = Path.of(output);
        } else if (Files.isDirectory(input)) {
            outPath = input.resolve(input.getFileName() + ".asm");
        } else {
            outPath = input.resolveSibling(baseName(input) + ".asm");
        }

        String asm = VmTranslator.translate(sources, bootstrap);
        Files.writeString(outPath, asm);

        long asmLines = asm.lines()
            .filter(l -> !l.isBlank() && !l.strip().startsWith("//")
                      && !(l.strip().startsWith("(") && l.strip().endsWith(")")))
            .count();
        System.out.println("[vm] " + sources.size() + " Datei(en) → " + outPath + " (" + asmLines + " ASM-Zeilen)");
    }

    // ── jack ─────────────────────────────────────────────────────────────────

    private static void runJack(String[] args) throws Exception {
        String source = null;
        for (String a : args) { if (source == null) source = a; }
        if (source == null) { System.err.println("Verwendung: jack <datei.jack|dir>"); System.exit(1); }

        Path input = Path.of(source);
        List<Path> sources = JackCompiler.collectSources(input);
        JackCompiler.compile(sources);
    }

    // ── build ─────────────────────────────────────────────────────────────────
    // jack → vm → asm → [load]

    private static void runBuild(String[] args) throws Exception {
        String source = null, ip = null, user = "root";
        boolean doLoad = false;

        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "--ip"   -> { ip = args[++i]; doLoad = true; }
                case "--user" -> user = args[++i];
                default -> { if (source == null) source = args[i]; }
            }
        }
        if (source == null) { System.err.println("Verwendung: build <datei.jack|dir> [--ip <ip>] [--user <user>]"); System.exit(1); }

        Path input = Path.of(source);

        // jack → vm
        List<Path> jackSources = JackCompiler.collectSources(input);
        List<Path> vmFiles = JackCompiler.compile(jackSources);

        // vm → asm
        Path asmOut = vmFiles.get(0).resolveSibling(
            (Files.isDirectory(input) ? input.getFileName() : baseName(input)) + ".asm");
        String asmCode = VmTranslator.translate(vmFiles, true);
        Files.writeString(asmOut, asmCode);
        System.out.println("[build] VM → " + asmOut.getFileName());

        // asm → hack
        Assembler asm = new Assembler(Files.readAllLines(asmOut));
        List<String> instructions = asm.assemble();
        Path hackOut = asmOut.resolveSibling(baseName(asmOut) + ".hack");
        Files.writeString(hackOut, String.join("\n", instructions) + "\n");
        System.out.println("[build] ASM → " + hackOut.getFileName() + " (" + instructions.size() + " Instruktionen)");

        if (doLoad) new HpsLoader(ip, user).load(hackOut);
    }

    // ── load ─────────────────────────────────────────────────────────────────

    private static void runLoad(String[] args) throws Exception {
        String hackFile = null, ip = null, user = "root";

        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "--ip"   -> ip   = args[++i];
                case "--user" -> user = args[++i];
                default -> { if (hackFile == null) hackFile = args[i]; }
            }
        }
        if (hackFile == null || ip == null) {
            System.err.println("Verwendung: load <datei.hack> --ip <ip> [--user <user>]");
            System.exit(1);
        }

        new HpsLoader(ip, user).load(Path.of(hackFile));
    }

    // ── helpers ───────────────────────────────────────────────────────────────

    private static String baseName(Path p) {
        String name = p.getFileName().toString();
        int dot = name.lastIndexOf('.');
        return dot >= 0 ? name.substring(0, dot) : name;
    }

    private static void printHelp() {
        System.out.println("""
            Atlas 16 Toolchain  —  https://atlas16.natalnetwork.com.br

            Befehle:
              jack  <datei.jack|dir>              Jack → VM
              vm    <datei.vm|dir>   [-o out.asm] [--no-bootstrap]  VM → ASM
              asm   <datei.asm>      [-o out.hack] [--bin]          ASM → Hack
              load  <datei.hack>     --ip <ip>    [--user <user>]   Hack → Atlas 16
              build <datei.jack|dir> [--ip <ip>]  [--user <user>]   Jack → Atlas 16
            """);
    }
}
