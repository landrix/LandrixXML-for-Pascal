<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- current() after a function call and in numbering patterns; a
     variable in a count pattern -->
<xsl:function name="f:id"><xsl:param name="p"/><xsl:sequence select="$p"/></xsl:function>
<xsl:variable name="g"><xsl:value-of select="f:id('g')"/></xsl:variable>
<xsl:template match="/">
  <r a="{count((f:id(1), current()))}" b="{count(($g, current()))}">
    <xsl:for-each select="/*">
      <n><xsl:number count="*[. is current()]"/></n>
    </xsl:for-each>
    <xsl:variable name="k" select="1"/>
    <m><xsl:number select="/*" count="*[position() = $k]"/></m>
  </r>
</xsl:template>
</xsl:stylesheet>
