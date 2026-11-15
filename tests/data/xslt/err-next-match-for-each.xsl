<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- XTDE0560: xsl:for-each clears the current template rule -->
<xsl:template match="/"><r><xsl:for-each select="."><xsl:next-match/></xsl:for-each></r></xsl:template>
</xsl:stylesheet>
