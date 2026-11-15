<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- XTDE0700: a required tunnel parameter that is not supplied -->
<xsl:template match="/"><r><xsl:call-template name="n"/></r></xsl:template>
<xsl:template name="n"><xsl:param name="p" tunnel="yes" required="yes"/></xsl:template>
</xsl:stylesheet>
