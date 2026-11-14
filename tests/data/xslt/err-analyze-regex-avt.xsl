<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xs="http://www.w3.org/2001/XMLSchema">
<!-- an invalid regular expression computed at run time -->
<xsl:template match="/"><r><xsl:analyze-string select="'a'" regex="{concat('(', 'a')}"><xsl:matching-substring/></xsl:analyze-string></r></xsl:template>
</xsl:stylesheet>
