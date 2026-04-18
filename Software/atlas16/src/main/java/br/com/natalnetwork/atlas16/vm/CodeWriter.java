package br.com.natalnetwork.atlas16.vm;

import java.util.*;

public class CodeWriter {

    private final List<String> out = new ArrayList<>();
    private int labelCounter = 0;
    private String currentFunc = "";
    private String currentFile = "";

    public CodeWriter(boolean bootstrap) {
        if (bootstrap) writeBootstrap();
    }

    public void setFile(String vmFilename) {
        int slash = vmFilename.lastIndexOf('/');
        String name = slash >= 0 ? vmFilename.substring(slash + 1) : vmFilename;
        if (name.endsWith(".vm")) name = name.substring(0, name.length() - 3);
        currentFile = name;
    }

    public void writeArithmetic(String cmd) {
        emit("// " + cmd);
        switch (cmd) {
            case "add" -> binary("D+M");
            case "sub" -> binary("M-D");
            case "neg" -> unary("-M");
            case "not" -> unary("!M");
            case "and" -> binary("D&M");
            case "or"  -> binary("D|M");
            case "eq"  -> compare("JEQ");
            case "gt"  -> compare("JGT");
            case "lt"  -> compare("JLT");
        }
    }

    public void writePushPop(String cmd, String segment, int index) {
        emit("// " + cmd + " " + segment + " " + index);
        if (cmd.equals("push")) push(segment, index);
        else                    pop(segment, index);
    }

    public void writeLabel(String label) {
        emit("// label " + label);
        String full = currentFunc.isEmpty() ? label : currentFunc + "$" + label;
        emit("(" + full + ")");
    }

    public void writeGoto(String label) {
        emit("// goto " + label);
        String full = currentFunc.isEmpty() ? label : currentFunc + "$" + label;
        emit("    @" + full);
        emit("    0;JMP");
    }

    public void writeIfGoto(String label) {
        emit("// if-goto " + label);
        String full = currentFunc.isEmpty() ? label : currentFunc + "$" + label;
        popD();
        emit("    @" + full);
        emit("    D;JNE");
    }

    public void writeFunction(String name, int nLocals) {
        emit("// function " + name + " " + nLocals);
        currentFunc = name;
        emit("(" + name + ")");
        for (int i = 0; i < nLocals; i++) {
            emit("    @0");
            emit("    D=A");
            pushD();
        }
    }

    public void writeCall(String name, int nArgs) {
        emit("// call " + name + " " + nArgs);
        String ret = name + "$ret." + unique();
        emit("    @" + ret);
        emit("    D=A");
        pushD();
        for (String sym : List.of("LCL", "ARG", "THIS", "THAT")) {
            emit("    @" + sym);
            emit("    D=M");
            pushD();
        }
        emit("    @SP");
        emit("    D=M");
        emit("    @" + (nArgs + 5));
        emit("    D=D-A");
        emit("    @ARG");
        emit("    M=D");
        emit("    @SP");
        emit("    D=M");
        emit("    @LCL");
        emit("    M=D");
        emit("    @" + name);
        emit("    0;JMP");
        emit("(" + ret + ")");
    }

    public void writeReturn() {
        emit("// return");
        emit("    @LCL");  emit("    D=M");  emit("    @R11"); emit("    M=D");
        emit("    @5");    emit("    A=D-A"); emit("    D=M");  emit("    @R12"); emit("    M=D");
        popD();
        emit("    @ARG");  emit("    A=M");  emit("    M=D");
        emit("    @ARG");  emit("    D=M+1"); emit("    @SP");  emit("    M=D");
        int i = 1;
        for (String sym : List.of("THAT", "THIS", "ARG", "LCL")) {
            emit("    @R11"); emit("    D=M");
            emit("    @" + i++);
            emit("    A=D-A"); emit("    D=M");
            emit("    @" + sym); emit("    M=D");
        }
        emit("    @R12"); emit("    A=M"); emit("    0;JMP");
    }

    public String close(boolean addAtlas16Lib) {
        String end = "$$END." + unique();
        emit("(" + end + ")");
        emit("    @" + end);
        emit("    0;JMP");
        if (addAtlas16Lib) out.addAll(List.of(Atlas16Stdlib.CODE.split("\n")));
        return String.join("\n", out) + "\n";
    }

    // ── private helpers ──────────────────────────────────────────────────────

    private void emit(String line) { out.add(line); }

    private int unique() { return ++labelCounter; }

    private void pushD() {
        emit("    @SP"); emit("    A=M"); emit("    M=D");
        emit("    @SP"); emit("    M=M+1");
    }

    private void popD() {
        emit("    @SP"); emit("    AM=M-1"); emit("    D=M");
    }

    private void binary(String op) {
        popD();
        emit("    A=A-1");
        emit("    M=" + op);
    }

    private void unary(String op) {
        emit("    @SP"); emit("    A=M-1"); emit("    M=" + op);
    }

    private void compare(String jmp) {
        int uid = unique();
        String trueL = "$$TRUE." + uid, endL = "$$END." + uid;
        popD();
        emit("    A=A-1"); emit("    D=M-D");
        emit("    @" + trueL); emit("    D;" + jmp);
        emit("    @SP"); emit("    A=M-1"); emit("    M=0");
        emit("    @" + endL); emit("    0;JMP");
        emit("(" + trueL + ")");
        emit("    @SP"); emit("    A=M-1"); emit("    M=-1");
        emit("(" + endL + ")");
    }

    private void push(String segment, int index) {
        switch (segment) {
            case "constant" -> { emit("    @" + index); emit("    D=A"); }
            case "local", "argument", "this", "that" -> {
                String base = Map.of("local","LCL","argument","ARG","this","THIS","that","THAT").get(segment);
                emit("    @" + index); emit("    D=A");
                emit("    @" + base); emit("    A=D+M"); emit("    D=M");
            }
            case "temp"    -> { emit("    @R" + (5 + index)); emit("    D=M"); }
            case "pointer" -> { emit("    @" + (index == 0 ? "THIS" : "THAT")); emit("    D=M"); }
            case "static"  -> { emit("    @" + currentFile + "." + index); emit("    D=M"); }
        }
        pushD();
    }

    private void pop(String segment, int index) {
        switch (segment) {
            case "local", "argument", "this", "that" -> {
                String base = Map.of("local","LCL","argument","ARG","this","THIS","that","THAT").get(segment);
                emit("    @" + index); emit("    D=A");
                emit("    @" + base); emit("    D=D+M");
                emit("    @R13"); emit("    M=D");
                popD();
                emit("    @R13"); emit("    A=M"); emit("    M=D");
            }
            case "temp"    -> { popD(); emit("    @R" + (5 + index)); emit("    M=D"); }
            case "pointer" -> { popD(); emit("    @" + (index == 0 ? "THIS" : "THAT")); emit("    M=D"); }
            case "static"  -> { popD(); emit("    @" + currentFile + "." + index); emit("    M=D"); }
        }
    }

    private void writeBootstrap() {
        emit("// Bootstrap: SP = 256, call Sys.init");
        emit("    @256"); emit("    D=A"); emit("    @SP"); emit("    M=D");
        writeCall("Sys.init", 0);
    }
}
