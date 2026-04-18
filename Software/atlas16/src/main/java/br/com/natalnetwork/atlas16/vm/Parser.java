package br.com.natalnetwork.atlas16.vm;

import br.com.natalnetwork.atlas16.common.AssemblerException;

import java.io.*;
import java.nio.file.*;
import java.util.*;

public class Parser {

    private static final Set<String> ARITH_OPS = Set.of(
        "add", "sub", "neg", "eq", "gt", "lt", "and", "or", "not"
    );

    public record Command(String kind, String arg1, int arg2) {
        public Command(String kind, String arg1) { this(kind, arg1, 0); }
        public Command(String kind)              { this(kind, "",   0); }
    }

    public static List<Command> parseFile(Path path) throws IOException {
        List<Command> cmds = new ArrayList<>();
        int lineno = 0;
        for (String raw : Files.readAllLines(path)) {
            lineno++;
            String line = raw.contains("//") ? raw.substring(0, raw.indexOf("//")) : raw;
            line = line.strip();
            if (line.isEmpty()) continue;

            String[] parts = line.split("\\s+");
            String cmd = parts[0].toLowerCase();

            if (ARITH_OPS.contains(cmd)) {
                cmds.add(new Command("arithmetic", cmd));
            } else if (cmd.equals("push") || cmd.equals("pop")) {
                if (parts.length != 3)
                    throw new AssemblerException(lineno, "Ungültiger " + cmd + "-Befehl: " + line);
                cmds.add(new Command(cmd, parts[1], Integer.parseInt(parts[2])));
            } else if (cmd.equals("label")) {
                cmds.add(new Command("label", parts[1]));
            } else if (cmd.equals("goto")) {
                cmds.add(new Command("goto", parts[1]));
            } else if (cmd.equals("if-goto")) {
                cmds.add(new Command("if-goto", parts[1]));
            } else if (cmd.equals("function")) {
                cmds.add(new Command("function", parts[1], Integer.parseInt(parts[2])));
            } else if (cmd.equals("call")) {
                cmds.add(new Command("call", parts[1], Integer.parseInt(parts[2])));
            } else if (cmd.equals("return")) {
                cmds.add(new Command("return"));
            } else {
                throw new AssemblerException(lineno, "Unbekannter VM-Befehl: " + cmd);
            }
        }
        return cmds;
    }
}
