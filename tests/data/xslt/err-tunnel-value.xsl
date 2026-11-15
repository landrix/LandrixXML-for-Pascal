<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- XTSE0020: tunnel is yes or no -->
<xsl:template match="/"><r><xsl:call-template name="n"><xsl:with-param name="p" tunnel="maybe"/></xsl:call-template></r></xsl:template>
<xsl:template name="n"/>
</xsl:stylesheet>
