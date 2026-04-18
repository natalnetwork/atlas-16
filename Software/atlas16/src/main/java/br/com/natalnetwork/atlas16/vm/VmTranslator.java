package br.com.natalnetwork.atlas16.vm;

import java.io.*;
import java.nio.file.*;
import java.util.*;

public class VmTranslator {

    public static String translate(List<Path> sources, boolean bootstrap) throws IOException {
        boolean needsAtlas16 = false;
        for (Path src : sources) {
            if (Files.readString(src).contains("Atlas16.")) {
                needsAtlas16 = true;
                break;
            }
        }

        CodeWriter writer = new CodeWriter(bootstrap);
        for (Path src : sources) {
            writer.setFile(src.toString());
            for (Parser.Command cmd : Parser.parseFile(src)) {
                switch (cmd.kind()) {
                    case "arithmetic" -> writer.writeArithmetic(cmd.arg1());
                    case "push", "pop" -> writer.writePushPop(cmd.kind(), cmd.arg1(), cmd.arg2());
                    case "label"       -> writer.writeLabel(cmd.arg1());
                    case "goto"        -> writer.writeGoto(cmd.arg1());
                    case "if-goto"     -> writer.writeIfGoto(cmd.arg1());
                    case "function"    -> writer.writeFunction(cmd.arg1(), cmd.arg2());
                    case "call"        -> writer.writeCall(cmd.arg1(), cmd.arg2());
                    case "return"      -> writer.writeReturn();
                }
            }
        }
        return writer.close(needsAtlas16);
    }

    public static List<Path> collectSources(Path input) throws IOException {
        if (Files.isRegularFile(input)) {
            return List.of(input);
        }
        List<Path> files = new ArrayList<>();
        try (var s = Files.list(input)) {
            s.filter(p -> p.toString().endsWith(".vm"))
             .sorted()
             .forEach(files::add);
        }
        if (files.isEmpty())
            throw new IOException("Keine .vm-Dateien in: " + input);
        return files;
    }
}
