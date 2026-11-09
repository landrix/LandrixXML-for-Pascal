/*
 * LandrixXml - dependency-free XML library for Delphi and Free Pascal.
 *
 * Copyright (c) 2026 Landrix Software
 * Licensed under the MIT License. See the LICENSE file in the project root
 * or https://opensource.org/licenses/MIT for the full license text.
 *
 * Test oracle only, never part of the library: validates XML documents
 * with the XML Schema validator built into the Java runtime (Xerces), the
 * one the KoSIT validator uses, and prints every error as
 *
 *   file TAB line TAB column TAB code TAB message
 *
 * where code is the leading identifier of the message ("cvc-...", or a
 * Xerces key such as "UndeclaredPrefix"). Messages
 * are English and UTF-8 encoded; control characters appear as U+XXXX.
 * If the JDK's validator throws a runtime exception for a document (it
 * does when an element exceeds a counted maxOccurs), the line reads
 * file TAB 0 TAB 0 TAB jdk-exception TAB class.
 * Exit code 0 even if documents are invalid; 2 on usage or schema errors.
 *
 *   javac --release 17 -d OUT tools/XsdOracle.java
 *   java -cp OUT XsdOracle schema.xsd instance1.xml [instance2.xml ...]
 */

import java.io.File;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.PrintStream;
import java.util.Locale;
import javax.xml.XMLConstants;
import javax.xml.transform.stream.StreamSource;
import javax.xml.validation.Schema;
import javax.xml.validation.SchemaFactory;
import javax.xml.validation.Validator;
import org.xml.sax.ErrorHandler;
import org.xml.sax.SAXParseException;

public class XsdOracle {
    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("usage: XsdOracle schema.xsd instance.xml ...");
            System.exit(2);
        }
        Locale.setDefault(Locale.ENGLISH);
        // UTF-8 output whatever the platform encoding
        System.setOut(new PrintStream(new FileOutputStream(FileDescriptor.out), true, "UTF-8"));
        SchemaFactory factory = SchemaFactory.newInstance(XMLConstants.W3C_XML_SCHEMA_NS_URI);
        Schema schema;
        try {
            schema = factory.newSchema(new File(args[0]));
        } catch (SAXParseException e) {
            System.err.println("schema error: " + e.getMessage());
            System.exit(2);
            return;
        }
        for (int i = 1; i < args.length; i++) {
            final String name = args[i];
            Validator validator = schema.newValidator();
            validator.setErrorHandler(new ErrorHandler() {
                public void warning(SAXParseException e) { }
                public void error(SAXParseException e) { print(name, e); }
                public void fatalError(SAXParseException e) { print(name, e); }
            });
            try {
                validator.validate(new StreamSource(new File(name)));
            } catch (SAXParseException e) {
                // already reported through fatalError
            } catch (RuntimeException e) {
                // the JDK's validator fails on some inputs (a message key
                // missing from its resources); report it and go on
                System.out.println(name + "\t0\t0\tjdk-exception\t" + e.getClass().getName());
            }
        }
    }

    // control characters (tabs, line feeds of values) as U+XXXX, so that a
    // message stays on one line without losing them
    static String escapeControls(String s) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c < 0x20) {
                b.append(String.format("U+%04X", (int) c));
            } else {
                b.append(c);
            }
        }
        return b.toString();
    }

    static void print(String name, SAXParseException e) {
        String message = escapeControls(e.getMessage() == null ? "" : e.getMessage());
        String code = "";
        int colon = message.indexOf(':');
        if (colon > 0 && message.substring(0, colon).matches("[A-Za-z][A-Za-z0-9.-]*")) {
            code = message.substring(0, colon);
            message = message.substring(colon + 1).trim();
        }
        System.out.println(name + "\t" + e.getLineNumber() + "\t" + e.getColumnNumber() + "\t" + code + "\t" + message);
    }
}
