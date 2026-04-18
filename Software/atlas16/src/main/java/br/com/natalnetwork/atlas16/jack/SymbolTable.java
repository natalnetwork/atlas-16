package br.com.natalnetwork.atlas16.jack;

import java.util.*;

public class SymbolTable {

    public enum Kind { STATIC, FIELD, ARG, VAR }

    private record Entry(String type, Kind kind, int index) {}

    private final Map<String, Entry> classScope      = new LinkedHashMap<>();
    private final Map<String, Entry> subroutineScope = new LinkedHashMap<>();
    private final Map<Kind, Integer> counts          = new EnumMap<>(Kind.class);

    public SymbolTable() {
        for (Kind k : Kind.values()) counts.put(k, 0);
    }

    public void startSubroutine() {
        subroutineScope.clear();
        counts.put(Kind.ARG, 0);
        counts.put(Kind.VAR, 0);
    }

    public void define(String name, String type, Kind kind) {
        int idx = counts.merge(kind, 1, Integer::sum) - 1;
        if (kind == Kind.STATIC || kind == Kind.FIELD)
            classScope.put(name, new Entry(type, kind, idx));
        else
            subroutineScope.put(name, new Entry(type, kind, idx));
    }

    public int varCount(Kind kind) { return counts.get(kind); }

    public boolean contains(String name) { return lookup(name) != null; }

    public Kind   kindOf(String name)  { return lookup(name).kind(); }
    public String typeOf(String name)  { return lookup(name).type(); }
    public int    indexOf(String name) { return lookup(name).index(); }

    private Entry lookup(String name) {
        Entry e = subroutineScope.get(name);
        return e != null ? e : classScope.get(name);
    }

    // Map Kind to VM segment name
    public static String segment(Kind kind) {
        return switch (kind) {
            case STATIC -> "static";
            case FIELD  -> "this";
            case ARG    -> "argument";
            case VAR    -> "local";
        };
    }
}
