<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- the select is converted to xs:string? as a function argument: no integer -->
<xsl:template match="/"><r><xsl:analyze-string select="22" regex="2"><xsl:matching-substring/></xsl:analyze-string></r></xsl:template>
</xsl:stylesheet>
