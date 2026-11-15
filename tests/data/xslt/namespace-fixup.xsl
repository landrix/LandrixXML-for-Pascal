<?xml version="1.0" encoding="UTF-8"?>
<!-- Namespace fixup as Saxon does it: an attribute keeps its own prefix
     where nothing on the element binds it otherwise (also with another
     prefix for the URI in scope or excluded), a renamed attribute prefix
     counts from the attribute's position, an element without a prefix
     whose default namespace xsl:namespace binds otherwise becomes _0. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <out>
      <a xmlns:p="urn:u" xmlns:q="urn:u" xsl:exclude-result-prefixes="#all" p:a="1" q:b="2"/>
      <b xmlns:q="urn:a"><xsl:attribute name="p:a" namespace="urn:a"/></b>
      <c><xsl:attribute name="p:a" namespace="urn:a"/><xsl:attribute name="q:b" namespace="urn:a"/></c>
      <d xmlns:q="urn:a" xsl:exclude-result-prefixes="q"><e q:z="1"><xsl:attribute name="p:a" namespace="urn:a"/></e></d>
      <f><xsl:attribute name="p:a" namespace="urn:a"/><xsl:attribute name="x" select="1"/><xsl:attribute name="p:b" namespace="urn:b"/></f>
      <xsl:element name="g" namespace="urn:g"><xsl:namespace name="">urn:other</xsl:namespace></xsl:element>
    </out>
  </xsl:template>
</xsl:stylesheet>
