<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:a="urn:one" xmlns:xsl-internal-v0="urn:two" xmlns:xsl-internal-f="urn:three">
<!-- prefixes the processor makes (no clashes: Saxon numbers those with a
     counter of its own); the xml prefix; stylesheet prefixes that
     look like internal ones -->
<xsl:variable name="a:v" select="'one'"/>
<xsl:variable name="xsl-internal-v0:v" select="'two'"/>
<xsl:variable name="xsl-internal-f:v" select="'three'"/>
<xsl:template match="/">
  <r v="{$a:v} {$xsl-internal-v0:v} {$xsl-internal-f:v}">
    <xsl:attribute name="a" namespace="urn:y">1</xsl:attribute>
    <xsl:attribute name="d" namespace="http://www.w3.org/XML/1998/namespace">4</xsl:attribute>
    <xsl:element name="xml:e" namespace="urn:e"/>
    <xsl:element name="f"><xsl:attribute name="g" namespace="urn:g">5</xsl:attribute></xsl:element>
  </r>
</xsl:template>
</xsl:stylesheet>
