package br.com.natalnetwork.atlas16.jack;

import java.util.Set;

public enum Keyword {
    CLASS, CONSTRUCTOR, FUNCTION, METHOD,
    FIELD, STATIC, VAR,
    INT, CHAR, BOOLEAN, VOID,
    TRUE, FALSE, NULL, THIS,
    LET, DO, IF, ELSE, WHILE, RETURN;

    public static final Set<String> ALL = Set.of(
        "class","constructor","function","method",
        "field","static","var",
        "int","char","boolean","void",
        "true","false","null","this",
        "let","do","if","else","while","return"
    );

    public static Keyword of(String s) {
        return valueOf(s.toUpperCase());
    }
}
