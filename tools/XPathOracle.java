/*
 * LandrixXml - dependency-free XML library for Delphi and Free Pascal.
 *
 * Copyright (c) 2026 Landrix Software
 * Licensed under the MIT License. See the LICENSE file in the project root
 * or https://opensource.org/licenses/MIT for the full license text.
 *
 * Test oracle only, never part of the library: evaluates XPath expressions
 * with Saxon HE (the processor inside the KoSIT validator) and prints the
 * results in the format of the library's tests:
 *
 *   # EXPRESSION
 *   TYPE VALUE          one line per atomic item (xs:integer 3)
 *   node LOCATION       one line per node, location as SchXslt writes it
 *   error CODE          a static or dynamic error (XPTY0004, FORG0001, ...)
 *
 * Control characters and the backslash in values appear as \xHH.
 * The cases file has lines "ns PREFIX URI" and "expr EXPRESSION"; the
 * context item is the document node.
 *
 *   javac -cp validator-1.6.3-standalone.jar -d OUT tools/XPathOracle.java
 *   java -cp OUT;validator-1.6.3-standalone.jar XPathOracle doc.xml cases.txt
 */

import java.io.File;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.List;
import net.sf.saxon.s9api.DocumentBuilder;
import net.sf.saxon.s9api.Processor;
import net.sf.saxon.s9api.SaxonApiException;
import net.sf.saxon.s9api.XPathCompiler;
import net.sf.saxon.s9api.XPathSelector;
import net.sf.saxon.s9api.XdmAtomicValue;
import net.sf.saxon.s9api.XdmItem;
import net.sf.saxon.s9api.XdmNode;
import net.sf.saxon.s9api.XdmNodeKind;
import net.sf.saxon.s9api.XdmValue;
import net.sf.saxon.s9api.Axis;
import net.sf.saxon.s9api.XdmSequenceIterator;

public class XPathOracle {
    public static void main(String[] args) throws Exception {
        PrintStream out = new PrintStream(new FileOutputStream(FileDescriptor.out), true, "UTF-8");
        Processor proc = new Processor(false);
        DocumentBuilder db = proc.newDocumentBuilder();
        XdmNode doc = db.build(new File(args[0]));
        XPathCompiler xc = proc.newXPathCompiler();
        List<String> lines = Files.readAllLines(new File(args[1]).toPath(), StandardCharsets.UTF_8);
        for (String line : lines) {
            if (line.startsWith("ns ")) {
                String[] p = line.substring(3).split(" ", 2);
                xc.declareNamespace(p[0], p[1]);
            } else if (line.startsWith("expr ")) {
                String expr = line.substring(5);
                out.println("# " + expr);
                try {
                    XPathSelector sel = xc.compile(expr).load();
                    sel.setContextItem(doc);
                    XdmValue v = sel.evaluate();
                    for (XdmItem item : v) {
                        if (item instanceof XdmNode) {
                            out.println("node " + esc(location((XdmNode) item)));
                        } else {
                            XdmAtomicValue a = (XdmAtomicValue) item;
                            out.println(typeName(a) + " " + esc(a.getStringValue()));
                        }
                    }
                } catch (SaxonApiException e) {
                    String code = e.getErrorCode() == null ? "unknown" : e.getErrorCode().getLocalName();
                    out.println("error " + code);
                }
            }
        }
    }

    static String typeName(XdmAtomicValue a) {
        String t = a.getTypeName().getEQName();
        String xs = "Q{http://www.w3.org/2001/XMLSchema}";
        if (t.startsWith(xs)) {
            t = "xs:" + t.substring(xs.length());
        }
        return t;
    }

    static String esc(String s) {
        StringBuilder b = new StringBuilder();
        byte[] bytes = s.getBytes(StandardCharsets.UTF_8);
        String out = new String(bytes, StandardCharsets.UTF_8);
        for (int i = 0; i < out.length(); i++) {
            char c = out.charAt(i);
            if (c < 32 || c == '\\') {
                b.append(String.format("\\x%02X", (int) c));
            } else {
                b.append(c);
            }
        }
        return b.toString();
    }

    /* The location as SchXslt's schxslt:location writes it. */
    static String location(XdmNode n) {
        StringBuilder b = new StringBuilder();
        XdmNode cur = n;
        while (cur != null && cur.getNodeKind() != XdmNodeKind.DOCUMENT) {
            String seg;
            switch (cur.getNodeKind()) {
                case ATTRIBUTE:
                    seg = "@Q{" + uri(cur) + "}" + cur.getNodeName().getLocalName();
                    break;
                case ELEMENT:
                    seg = "Q{" + uri(cur) + "}" + cur.getNodeName().getLocalName() + "[" + position(cur) + "]";
                    break;
                case TEXT:
                    seg = "text()[" + position(cur) + "]";
                    break;
                case COMMENT:
                    seg = "comment()[" + position(cur) + "]";
                    break;
                case PROCESSING_INSTRUCTION:
                    seg = "processing-instruction(\"" + cur.getNodeName().getLocalName() + "\")[" + position(cur) + "]";
                    break;
                default:
                    seg = "";
            }
            b.insert(0, "/" + seg);
            cur = cur.getParent();
        }
        return b.length() == 0 ? "/" : b.toString();
    }

    static String uri(XdmNode n) {
        return n.getNodeName().getNamespaceUri().toString();
    }

    static int position(XdmNode n) {
        int p = 1;
        XdmSequenceIterator<XdmNode> it = n.axisIterator(Axis.PRECEDING_SIBLING);
        while (it.hasNext()) {
            XdmNode s = it.next();
            if (s.getNodeKind() == n.getNodeKind()
                    && (s.getNodeName() == null || s.getNodeName().equals(n.getNodeName()))) {
                p++;
            }
        }
        return p;
    }
}
