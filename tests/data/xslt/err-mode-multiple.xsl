<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- on-multiple-match="fail" and two rules -->
<xsl:mode on-multiple-match="fail"/><xsl:template match="doc"><xsl:apply-templates/></xsl:template><xsl:template match="*"/><xsl:template match="node()"/>
<xsl:template match="/"><r><xsl:apply-templates select="doc"/></r></xsl:template>
</xsl:stylesheet>
