<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- XTSE0680: a parameter that is no tunnel parameter for a template that
     has only a tunnel parameter of that name -->
<xsl:template match="/"><r><xsl:call-template name="n"><xsl:with-param name="p" select="1"/></xsl:call-template></r></xsl:template>
<xsl:template name="n"><xsl:param name="p" tunnel="yes"/></xsl:template>
</xsl:stylesheet>
