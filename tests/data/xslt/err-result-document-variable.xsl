<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- XTDE1480: xsl:result-document in a temporary output state -->
<xsl:template match="/"><xsl:variable name="v"><xsl:result-document><r/></xsl:result-document></xsl:variable><xsl:copy-of select="$v"/></xsl:template>
</xsl:stylesheet>
