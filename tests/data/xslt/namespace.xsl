<?xml version="1.0" encoding="UTF-8"?>
<!-- xsl:namespace: select and content (items joined with a space), the
     prefix and the URI without surrounding white space, the default
     namespace of an element in that namespace, the same binding twice,
     the xml prefix, a prefix of an attribute or of the element that the
     namespace node binds otherwise (another prefix: _1 for an attribute,
     _0 for the element, as Saxon), an excluded namespace the element uses,
     xsl:element and xsl:copy. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <out>
      <a><xsl:namespace name="p">urn:p</xsl:namespace></a>
      <b><xsl:namespace name="p" select="'urn', 'b'"/></b>
      <c><xsl:namespace name="p"><xsl:sequence select="'urn', 'c'"/></xsl:namespace></c>
      <d><xsl:namespace name=" {'p'} "> urn:d </xsl:namespace></d>
      <e xmlns="urn:e"><xsl:namespace name="">urn:e</xsl:namespace></e>
      <f><xsl:namespace name="p">urn:f</xsl:namespace><xsl:namespace name="p">urn:f</xsl:namespace></f>
      <g><xsl:namespace name="xml">http://www.w3.org/XML/1998/namespace</xsl:namespace></g>
      <h><xsl:attribute name="p:a" namespace="urn:a">1</xsl:attribute><xsl:namespace name="p">urn:h</xsl:namespace></h>
      <xsl:element name="p:i" namespace="urn:a"><xsl:namespace name="p">urn:i</xsl:namespace></xsl:element>
      <p:j xmlns:p="urn:a" xsl:exclude-result-prefixes="p"><xsl:namespace name="p">urn:j</xsl:namespace></p:j>
      <xsl:for-each select="doc/k">
        <xsl:copy><xsl:namespace name="q">urn:k</xsl:namespace></xsl:copy>
      </xsl:for-each>
      <l><xsl:namespace name="p">urn:l</xsl:namespace><p:m xmlns:p="urn:m"/></l>
    </out>
  </xsl:template>
</xsl:stylesheet>
