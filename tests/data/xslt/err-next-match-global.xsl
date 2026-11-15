<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- XTDE0560: no current template rule in a global variable -->
<xsl:variable name="g"><xsl:apply-imports/></xsl:variable>
<xsl:template match="/"><r><xsl:copy-of select="$g"/></r></xsl:template>
</xsl:stylesheet>
