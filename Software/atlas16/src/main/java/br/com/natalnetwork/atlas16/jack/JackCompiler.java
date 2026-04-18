package br.com.natalnetwork.atlas16.jack;

import java.io.*;
import java.nio.file.*;
import java.util.*;

public class JackCompiler {

    public static List<Path> collectSources(Path input) throws IOException {
        if (Files.isRegularFile(input)) return List.of(input);
        List<Path> files = new ArrayList<>();
        try (var s = Files.list(input)) {
            s.filter(p -> p.toString().endsWith(".jack")).sorted().forEach(files::add);
        }
        if (files.isEmpty()) throw new IOException("Keine .jack-Dateien in: " + input);
        return files;
    }

    public static List<Path> compile(List<Path> sources) throws IOException {
        List<Path> outputs = new ArrayList<>();
        for (Path src : sources) {
            JackTokenizer tok = new JackTokenizer(src);
            CompilationEngine engine = new CompilationEngine(tok);
            String vm = engine.compile();

            Path out = src.resolveSibling(
                src.getFileName().toString().replace(".jack", ".vm"));
            Files.writeString(out, vm);
            System.out.println("[jack] " + src.getFileName() + " → " + out.getFileName());
            outputs.add(out);
        }
        return outputs;
    }
}
