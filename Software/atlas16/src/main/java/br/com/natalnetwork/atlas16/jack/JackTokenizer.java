package br.com.natalnetwork.atlas16.jack;

import br.com.natalnetwork.atlas16.common.AssemblerException;

import java.io.*;
import java.nio.file.*;
import java.util.*;

public class JackTokenizer {

    private final String src;
    private int pos = 0;

    private TokenType currentType;
    private String    currentRaw;   // raw text of current token

    public JackTokenizer(Path path) throws IOException {
        this.src = stripComments(Files.readString(path));
    }

    // Strip /* */ and // comments
    private static String stripComments(String s) {
        // Block comments (including /** ... */)
        s = s.replaceAll("/\\*[\\s\\S]*?\\*/", " ");
        // Line comments
        s = s.replaceAll("//[^\n]*", "");
        return s;
    }

    public boolean hasMoreTokens() {
        skipWhitespace();
        return pos < src.length();
    }

    public void advance() {
        skipWhitespace();
        if (pos >= src.length()) throw new NoSuchElementException("No more tokens");

        char c = src.charAt(pos);

        // String constant
        if (c == '"') {
            int end = src.indexOf('"', pos + 1);
            if (end < 0) throw new AssemblerException("Nicht geschlossener String");
            currentRaw  = src.substring(pos + 1, end);
            currentType = TokenType.STRING_CONST;
            pos = end + 1;
            return;
        }

        // Symbol
        if ("{}()[].,;+-*/&|<>=~".indexOf(c) >= 0) {
            currentRaw  = String.valueOf(c);
            currentType = TokenType.SYMBOL;
            pos++;
            return;
        }

        // Integer constant
        if (Character.isDigit(c)) {
            int start = pos;
            while (pos < src.length() && Character.isDigit(src.charAt(pos))) pos++;
            currentRaw  = src.substring(start, pos);
            currentType = TokenType.INT_CONST;
            return;
        }

        // Keyword or identifier
        if (Character.isLetter(c) || c == '_') {
            int start = pos;
            while (pos < src.length() && (Character.isLetterOrDigit(src.charAt(pos)) || src.charAt(pos) == '_'))
                pos++;
            currentRaw  = src.substring(start, pos);
            currentType = Keyword.ALL.contains(currentRaw) ? TokenType.KEYWORD : TokenType.IDENTIFIER;
            return;
        }

        throw new AssemblerException("Unbekanntes Zeichen: '" + c + "' an Position " + pos);
    }

    private void skipWhitespace() {
        while (pos < src.length() && Character.isWhitespace(src.charAt(pos))) pos++;
    }

    // ── Accessors ─────────────────────────────────────────────────────────────

    public TokenType tokenType()  { return currentType; }
    public Keyword   keyword()    { return Keyword.of(currentRaw); }
    public char      symbol()     { return currentRaw.charAt(0); }
    public int       intVal()     { return Integer.parseInt(currentRaw); }
    public String    stringVal()  { return currentRaw; }
    public String    identifier() { return currentRaw; }

    // Peek-ahead: read next token, then push back
    private final Deque<String[]> pushback = new ArrayDeque<>();

    public void pushBack() {
        pushback.push(new String[]{ currentType.name(), currentRaw });
        // rewind pos is not trivial, so we use pushback queue
    }

    // internal: advance accounting for pushback
    public void advanceFull() {
        if (!pushback.isEmpty()) {
            String[] t = pushback.pop();
            currentType = TokenType.valueOf(t[0]);
            currentRaw  = t[1];
        } else {
            advance();
        }
    }

    public boolean hasMoreFull() {
        return !pushback.isEmpty() || hasMoreTokens();
    }
}
