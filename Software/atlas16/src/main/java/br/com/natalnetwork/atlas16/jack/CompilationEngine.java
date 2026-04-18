package br.com.natalnetwork.atlas16.jack;

import br.com.natalnetwork.atlas16.common.AssemblerException;

import java.util.*;

/**
 * Rekursiver Abstieg: Jack → VM-Code (gemäß [N2T] Kapitel 10–11).
 */
public class CompilationEngine {

    private final JackTokenizer tok;
    private final List<String>  vm  = new ArrayList<>();
    private final SymbolTable   sym = new SymbolTable();

    private String className;
    private int    labelCounter = 0;

    public CompilationEngine(JackTokenizer tok) {
        this.tok = tok;
    }

    public String compile() {
        compileClass();
        return String.join("\n", vm) + "\n";
    }

    // ── class ────────────────────────────────────────────────────────────────

    private void compileClass() {
        eat(Keyword.CLASS);
        className = eatIdentifier();
        eat('{');
        while (peekKeyword(Keyword.STATIC, Keyword.FIELD))
            compileClassVarDec();
        while (peekKeyword(Keyword.CONSTRUCTOR, Keyword.FUNCTION, Keyword.METHOD))
            compileSubroutine();
        eat('}');
    }

    private void compileClassVarDec() {
        Keyword kw = eatKeyword();                          // static | field
        SymbolTable.Kind kind = kw == Keyword.STATIC
                                ? SymbolTable.Kind.STATIC
                                : SymbolTable.Kind.FIELD;
        String type = eatType();
        sym.define(eatIdentifier(), type, kind);
        while (peekSymbol(',')) { eat(','); sym.define(eatIdentifier(), type, kind); }
        eat(';');
    }

    // ── subroutine ───────────────────────────────────────────────────────────

    private void compileSubroutine() {
        sym.startSubroutine();
        Keyword kw = eatKeyword();                          // constructor | function | method
        eatType();                                          // return type (void or type)
        String name = eatIdentifier();

        if (kw == Keyword.METHOD)
            sym.define("this", className, SymbolTable.Kind.ARG);

        eat('(');
        compileParameterList();
        eat(')');
        compileSubroutineBody(className + "." + name, kw);
    }

    private void compileParameterList() {
        if (peekSymbol(')')) return;
        String type = eatType();
        sym.define(eatIdentifier(), type, SymbolTable.Kind.ARG);
        while (peekSymbol(',')) {
            eat(',');
            type = eatType();
            sym.define(eatIdentifier(), type, SymbolTable.Kind.ARG);
        }
    }

    private void compileSubroutineBody(String fullName, Keyword kind) {
        eat('{');
        while (peekKeyword(Keyword.VAR)) compileVarDec();

        int nLocals = sym.varCount(SymbolTable.Kind.VAR);
        emit("function " + fullName + " " + nLocals);

        if (kind == Keyword.CONSTRUCTOR) {
            int nFields = sym.varCount(SymbolTable.Kind.FIELD);
            emit("push constant " + nFields);
            emit("call Memory.alloc 1");
            emit("pop pointer 0");
        } else if (kind == Keyword.METHOD) {
            emit("push argument 0");
            emit("pop pointer 0");
        }

        compileStatements();
        eat('}');
    }

    private void compileVarDec() {
        eat(Keyword.VAR);
        String type = eatType();
        sym.define(eatIdentifier(), type, SymbolTable.Kind.VAR);
        while (peekSymbol(',')) { eat(','); sym.define(eatIdentifier(), type, SymbolTable.Kind.VAR); }
        eat(';');
    }

    // ── statements ───────────────────────────────────────────────────────────

    private void compileStatements() {
        while (peekKeyword(Keyword.LET, Keyword.IF, Keyword.WHILE, Keyword.DO, Keyword.RETURN)) {
            Keyword kw = peekKeywordValue();
            switch (kw) {
                case LET    -> compileLet();
                case IF     -> compileIf();
                case WHILE  -> compileWhile();
                case DO     -> compileDo();
                case RETURN -> compileReturn();
                default     -> throw new AssemblerException("Unerwartetes Statement: " + kw);
            }
        }
    }

    private void compileLet() {
        eat(Keyword.LET);
        String name = eatIdentifier();
        boolean array = peekSymbol('[');
        if (array) {
            pushVar(name);
            eat('['); compileExpression(); eat(']');
            emit("add");
        }
        eat('=');
        compileExpression();
        eat(';');
        if (array) {
            emit("pop temp 0");
            emit("pop pointer 1");
            emit("push temp 0");
            emit("pop that 0");
        } else {
            popVar(name);
        }
    }

    private void compileIf() {
        String elseL = newLabel(), endL = newLabel();
        eat(Keyword.IF); eat('('); compileExpression(); eat(')');
        emit("not");
        emit("if-goto " + elseL);
        eat('{'); compileStatements(); eat('}');
        emit("goto " + endL);
        emit("label " + elseL);
        if (peekKeyword(Keyword.ELSE)) {
            eat(Keyword.ELSE); eat('{'); compileStatements(); eat('}');
        }
        emit("label " + endL);
    }

    private void compileWhile() {
        String topL = newLabel(), endL = newLabel();
        eat(Keyword.WHILE);
        emit("label " + topL);
        eat('('); compileExpression(); eat(')');
        emit("not");
        emit("if-goto " + endL);
        eat('{'); compileStatements(); eat('}');
        emit("goto " + topL);
        emit("label " + endL);
    }

    private void compileDo() {
        eat(Keyword.DO);
        advance();              // Bezeichner lesen, dann an compileSubroutineCall übergeben
        compileSubroutineCall();
        emit("pop temp 0");     // discard return value
        eat(';');
    }

    private void compileReturn() {
        eat(Keyword.RETURN);
        if (!peekSymbol(';')) compileExpression();
        else                  emit("push constant 0");  // void return
        eat(';');
        emit("return");
    }

    // ── expressions ──────────────────────────────────────────────────────────

    private static final String OPS = "+-*/&|<>=";

    private void compileExpression() {
        compileTerm();
        while (peekSymbolIn(OPS)) {
            char op = eatSymbol();
            compileTerm();
            emitOp(op);
        }
    }

    private void compileTerm() {
        advance();
        switch (tok.tokenType()) {
            case INT_CONST    -> emit("push constant " + tok.intVal());
            case STRING_CONST -> compileStringConst(tok.stringVal());
            case KEYWORD      -> {
                switch (tok.keyword()) {
                    case TRUE  -> { emit("push constant 1"); emit("neg"); }
                    case FALSE, NULL -> emit("push constant 0");
                    case THIS  -> emit("push pointer 0");
                    default -> throw new AssemblerException("Unerwartetes Keyword in Term: " + tok.keyword());
                }
            }
            case SYMBOL -> {
                char sym = tok.symbol();
                if (sym == '(') { compileExpression(); eat(')'); }
                else if (sym == '-') { compileTerm(); emit("neg"); }
                else if (sym == '~') { compileTerm(); emit("not"); }
                else throw new AssemblerException("Unerwartetes Symbol in Term: " + sym);
            }
            case IDENTIFIER -> {
                String name = tok.identifier();
                if (peekSymbol('[')) {
                    // array access
                    pushVar(name);
                    eat('['); compileExpression(); eat(']');
                    emit("add");
                    emit("pop pointer 1");
                    emit("push that 0");
                } else if (peekSymbol('(') || peekSymbol('.')) {
                    // subroutine call — push identifier back, delegate
                    tok.pushBack();
                    tok.advanceFull();  // re-read identifier
                    compileSubroutineCall();
                } else {
                    pushVar(name);
                }
            }
        }
    }

    private void compileSubroutineCall() {
        // current token is already the first identifier (class/object/subroutine name)
        String first = tok.identifier();
        int nArgs = 0;

        if (peekSymbol('.')) {
            eat('.');
            String sub = eatIdentifier();
            if (sym.contains(first)) {
                // method call on object variable
                pushVar(first);
                nArgs = 1;
                eat('(');
                nArgs += compileExpressionList();
                eat(')');
                emit("call " + sym.typeOf(first) + "." + sub + " " + nArgs);
            } else {
                // function/constructor call on class name
                eat('(');
                nArgs += compileExpressionList();
                eat(')');
                emit("call " + first + "." + sub + " " + nArgs);
            }
        } else {
            // implicit this — method call on current class
            emit("push pointer 0");
            nArgs = 1;
            eat('(');
            nArgs += compileExpressionList();
            eat(')');
            emit("call " + className + "." + first + " " + nArgs);
        }
    }

    private int compileExpressionList() {
        int n = 0;
        if (!peekSymbol(')')) {
            compileExpression(); n++;
            while (peekSymbol(',')) { eat(','); compileExpression(); n++; }
        }
        return n;
    }

    // ── VM helpers ────────────────────────────────────────────────────────────

    private void pushVar(String name) {
        if (sym.contains(name)) {
            emit("push " + SymbolTable.segment(sym.kindOf(name)) + " " + sym.indexOf(name));
        } else {
            throw new AssemblerException("Undefinierte Variable: " + name);
        }
    }

    private void popVar(String name) {
        if (sym.contains(name)) {
            emit("pop " + SymbolTable.segment(sym.kindOf(name)) + " " + sym.indexOf(name));
        } else {
            throw new AssemblerException("Undefinierte Variable: " + name);
        }
    }

    private void emitOp(char op) {
        switch (op) {
            case '+' -> emit("add");
            case '-' -> emit("sub");
            case '*' -> emit("call Math.multiply 2");
            case '/' -> emit("call Math.divide 2");
            case '&' -> emit("and");
            case '|' -> emit("or");
            case '<' -> emit("lt");
            case '>' -> emit("gt");
            case '=' -> emit("eq");
        }
    }

    private void compileStringConst(String s) {
        emit("push constant " + s.length());
        emit("call String.new 1");
        for (char c : s.toCharArray()) {
            emit("push constant " + (int) c);
            emit("call String.appendChar 2");
        }
    }

    private void emit(String line) { vm.add(line); }

    private String newLabel() { return className + "_L" + (++labelCounter); }

    // ── Token eating ─────────────────────────────────────────────────────────

    private void advance() {
        tok.advanceFull();
    }

    private void eat(Keyword expected) {
        advance();
        if (tok.tokenType() != TokenType.KEYWORD || tok.keyword() != expected)
            throw new AssemblerException("Erwartet '" + expected.name().toLowerCase() + "'");
    }

    private void eat(char expected) {
        advance();
        if (tok.tokenType() != TokenType.SYMBOL || tok.symbol() != expected)
            throw new AssemblerException("Erwartet '" + expected + "'");
    }

    private Keyword eatKeyword() {
        advance();
        if (tok.tokenType() != TokenType.KEYWORD)
            throw new AssemblerException("Keyword erwartet");
        return tok.keyword();
    }

    private char eatSymbol() {
        advance();
        if (tok.tokenType() != TokenType.SYMBOL)
            throw new AssemblerException("Symbol erwartet");
        return tok.symbol();
    }

    private String eatIdentifier() {
        advance();
        if (tok.tokenType() != TokenType.IDENTIFIER)
            throw new AssemblerException("Bezeichner erwartet, gefunden: "
                + tok.tokenType() + " '" + tok.identifier() + "'");
        return tok.identifier();
    }

    private String eatType() {
        advance();
        if (tok.tokenType() == TokenType.IDENTIFIER) return tok.identifier();
        if (tok.tokenType() == TokenType.KEYWORD) {
            Keyword kw = tok.keyword();
            if (kw == Keyword.INT || kw == Keyword.CHAR
                    || kw == Keyword.BOOLEAN || kw == Keyword.VOID)
                return kw.name().toLowerCase();
        }
        throw new AssemblerException("Typ erwartet");
    }

    // ── Peek helpers ──────────────────────────────────────────────────────────

    private boolean peekSymbol(char c) {
        if (!tok.hasMoreFull()) return false;
        tok.advanceFull();
        boolean match = tok.tokenType() == TokenType.SYMBOL && tok.symbol() == c;
        tok.pushBack();
        return match;
    }

    private boolean peekSymbolIn(String chars) {
        if (!tok.hasMoreFull()) return false;
        tok.advanceFull();
        boolean match = tok.tokenType() == TokenType.SYMBOL && chars.indexOf(tok.symbol()) >= 0;
        tok.pushBack();
        return match;
    }

    private boolean peekKeyword(Keyword... kws) {
        if (!tok.hasMoreFull()) return false;
        tok.advanceFull();
        boolean match = tok.tokenType() == TokenType.KEYWORD
                     && Arrays.asList(kws).contains(tok.keyword());
        tok.pushBack();
        return match;
    }

    private Keyword peekKeywordValue() {
        tok.advanceFull();
        Keyword kw = tok.keyword();
        tok.pushBack();
        return kw;
    }
}
