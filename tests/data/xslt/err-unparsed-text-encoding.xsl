<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- an encoding that is no string, the URI empty -->
<xsl:template match="/"><o><xsl:value-of select="unparsed-text((), 42)"/></o></xsl:template>
</xsl:stylesheet>
