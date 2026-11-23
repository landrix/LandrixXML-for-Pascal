<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- on-no-match="fail" and a node no rule matches -->
<xsl:mode on-no-match="fail"/><xsl:template match="doc"><xsl:apply-templates/></xsl:template><xsl:template match="a | b"/>
<xsl:template match="/"><r><xsl:apply-templates select="doc"/></r></xsl:template>
</xsl:stylesheet>
