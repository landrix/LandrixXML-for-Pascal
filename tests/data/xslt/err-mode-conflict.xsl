<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- two xsl:mode of one precedence with different values -->
<xsl:mode on-no-match="deep-copy"/><xsl:mode on-no-match="shallow-copy"/>
<xsl:template match="/"><r><xsl:apply-templates select="doc"/></r></xsl:template>
</xsl:stylesheet>
