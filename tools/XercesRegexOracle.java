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
 *   string TAB hex TAB hex           -> 1, 0 or E: does the string match
 *                                       the pattern (both as UTF-8 bytes
 *                                       in hex, so they may hold a TAB)
 *   ranges TAB pattern               -> the code points 0 to 10FFFF whose
 *                                       one-character string matches, as
 *                                       hex ranges "lo-hi lo-hi ...", or E
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
            String pattern = f[0].equals("string") ? fromHex(f[1]) : f[1];
            RegularExpression re = cache.get(pattern);
            if (re == null && !cache.containsKey(pattern)) {
                try {
                    re = new RegularExpression(pattern, "X");
                } catch (RuntimeException e) {
                    re = null;
                }
                cache.put(pattern, re);
            }
            if (f[0].equals("valid")) {
                out.println(re != null ? "1" : "0");
            } else if (re == null) {
                out.println("E");
            } else if (f[0].equals("ranges")) {
                StringBuilder b = new StringBuilder();
                int start = -1;
                for (int c = 0; c <= 0x110000; c++) {
                    boolean m = c < 0x110000 && re.matches(new String(Character.toChars(c)));
                    if (m && start < 0) {
                        start = c;
                    } else if (!m && start >= 0) {
                        if (b.length() > 0) {
                            b.append(' ');
                        }
                        b.append(Integer.toHexString(start)).append('-').append(Integer.toHexString(c - 1));
                        start = -1;
                    }
                }
                out.println(b.toString());
            } else if (f[0].equals("string")) {
                out.println(re.matches(fromHex(f[2])) ? "1" : "0");
            } else {
                String s = new String(Character.toChars(Integer.parseInt(f[2])));
                out.println(re.matches(s) ? "1" : "0");
            }
        }
        out.flush();
    }

    private static String fromHex(String hex) {
        byte[] bytes = new byte[hex.length() / 2];
        for (int i = 0; i < bytes.length; i++) {
            bytes[i] = (byte) Integer.parseInt(hex.substring(2 * i, 2 * i + 2), 16);
        }
        return new String(bytes, StandardCharsets.UTF_8);
    }
}
