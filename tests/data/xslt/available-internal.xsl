<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:i="urn:landrix:xslt-internal">
<!-- a stylesheet function in the namespace of the runtime's own functions
     is available; the runtime's global() is not -->
<xsl:output method="text"/>
<xsl:function name="i:global"><xsl:param name="x"/><xsl:sequence select="$x"/></xsl:function>
<xsl:template match="/">
  <xsl:value-of separator="|" select="function-available('i:global'), function-available('i:global', 1),
    i:global(42)"/>
</xsl:template>
</xsl:stylesheet>
