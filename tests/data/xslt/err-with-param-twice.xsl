<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- XTSE0670: two xsl:with-param with the same name (one a tunnel parameter) -->
<xsl:template match="/"><r><xsl:apply-templates><xsl:with-param name="p" select="1"/><xsl:with-param name="p" tunnel="yes" select="2"/></xsl:apply-templates></r></xsl:template>
</xsl:stylesheet>
