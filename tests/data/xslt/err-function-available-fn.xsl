<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- XTDE1400: the prefix fn is not declared in the stylesheet (the XPath
     context knows it, the name argument does not) -->
<xsl:template match="/"><o><xsl:value-of select="function-available('fn:true')"/></o></xsl:template>
</xsl:stylesheet>
