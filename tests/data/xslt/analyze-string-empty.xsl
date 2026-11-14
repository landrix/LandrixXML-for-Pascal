<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- an empty select is the empty string, as in Saxon -->
<xsl:template match="/"><r><xsl:analyze-string select="()" regex="2"><xsl:non-matching-substring>x</xsl:non-matching-substring></xsl:analyze-string>-</r></xsl:template>
</xsl:stylesheet>
