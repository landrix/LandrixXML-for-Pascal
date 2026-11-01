/*
 * LandrixXml - dependency-free XML library for Delphi and Free Pascal.
 *
 * Copyright (c) 2026 Landrix Software
 * Licensed under the MIT License. See the LICENSE file in the project root
 * or https://opensource.org/licenses/MIT for the full license text.
 *
 * Test oracle only, never part of the library: asks the XML Schema regular
 * expression engine of the Java runtime's Xerces (the one the KoSIT
 * validator uses for pattern facets) whether patterns are valid and which
 * characters they match. Reads lines from standard input:
 *
 *   valid TAB pattern                -> 1 or 0
 *   match TAB pattern TAB codepoint  -> 1, 0 or E (invalid pattern)
 *
 * and writes one answer line per input line. The engine is an internal
 * class of the java.xml module, hence the --add-exports options:
 *
 *   javac --add-exports java.xml/com.sun.org.apache.xerces.internal.impl.xpath.regex=ALL-UNNAMED -d OUT tools/XercesRegexOracle.java
 *   java --add-exports java.xml/com.sun.org.apache.xerces.internal.impl.xpath.regex=ALL-UNNAMED -cp OUT XercesRegexOracle
 */

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import com.sun.org.apache.xerces.internal.impl.xpath.regex.RegularExpression;

public class XercesRegexOracle {
    public static void main(String[] args) throws Exception {
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        PrintStream out = new PrintStream(System.out, false, "UTF-8");
        Map<String, RegularExpression> cache = new HashMap<>();
        String line;
        while ((line = in.readLine()) != null) {
            String[] f = line.split("\t", -1);
            RegularExpression re = cache.get(f[1]);
            if (re == null && !cache.containsKey(f[1])) {
                try {
                    re = new RegularExpression(f[1], "X");
                } catch (RuntimeException e) {
                    re = null;
                }
                cache.put(f[1], re);
            }
            if (f[0].equals("valid")) {
                out.println(re != null ? "1" : "0");
            } else if (re == null) {
                out.println("E");
            } else {
                String s = new String(Character.toChars(Integer.parseInt(f[2])));
                out.println(re.matches(s) ? "1" : "0");
            }
        }
        out.flush();
    }
}
