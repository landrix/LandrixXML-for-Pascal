<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- resolve-uri() with two URIs -->
<xsl:template match="/"><r><xsl:value-of select="resolve-uri(('a.xml', 'b.xml'))"/></r></xsl:template>
</xsl:stylesheet>
