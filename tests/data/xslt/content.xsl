<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- simple content: adjacent text nodes merged, empty ones dropped; a
     space between atomic values in comments and processing instructions;
     empty text nodes in sequences; xsl:copy of the document node -->
<xsl:output method="xml" exclude-result-prefixes="#all" extension-element-prefixes="" expand-text="no"/>
<xsl:template match="/">
  <xsl:variable name="v" as="text()*"><xsl:text>a</xsl:text><xsl:text>b</xsl:text></xsl:variable>
  <xsl:variable name="e" as="text()*"><xsl:value-of select="''"/></xsl:variable>
  <xsl:variable name="t" as="text()*"><xsl:text/></xsl:variable>
  <xsl:variable name="m" as="item()*"><xsl:text>x</xsl:text><xsl:value-of select="''"/><xsl:text>y</xsl:text><xsl:sequence select="1"/></xsl:variable>
  <r a="{$v}" n="{count($v)}" e="{count($e)}" t="{count($t)}" m="{$m}">
    <xsl:attribute name="b"><xsl:sequence select="(1,2)"/></xsl:attribute>
    <xsl:attribute name="c" select="$m" separator="|"/>
    <xsl:value-of select="$v" separator="|"/>
    <xsl:comment><xsl:sequence select="(1,2)"/></xsl:comment>
    <xsl:processing-instruction name="p"><xsl:sequence select="('a','b')"/></xsl:processing-instruction>
    <f><xsl:sequence select="1"/><xsl:value-of select="''"/><xsl:sequence select="2"/><xsl:text/><xsl:sequence select="3"/></f>
    <d><xsl:sequence select="1"/><xsl:copy><xsl:sequence select="2"/></xsl:copy><xsl:sequence select="3"/></d>
  </r>
</xsl:template>
</xsl:stylesheet>
