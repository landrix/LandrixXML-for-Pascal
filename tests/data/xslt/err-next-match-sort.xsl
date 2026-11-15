<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- XTDE0560: no current template rule in a sort key -->
<xsl:template match="/"><r><xsl:apply-templates select="doc"><xsl:sort><xsl:next-match/></xsl:sort></xsl:apply-templates></r></xsl:template>
</xsl:stylesheet>
