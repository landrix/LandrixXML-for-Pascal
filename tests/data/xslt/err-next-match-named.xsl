<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- XTDE0560: a named template keeps the current template rule,
     xsl:for-each-group clears it -->
<xsl:template match="/"><r><xsl:call-template name="n"/></r></xsl:template>
<xsl:template name="n"><xsl:for-each-group select="1" group-by="."><xsl:apply-imports/></xsl:for-each-group></xsl:template>
</xsl:stylesheet>
