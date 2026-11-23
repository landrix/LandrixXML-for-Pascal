<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- a mode name in a reserved namespace -->
<xsl:template match="/" mode="Q{http://www.w3.org/2005/xpath-functions/map}m"><r/></xsl:template>
<xsl:template match="/"><r><xsl:apply-templates select="doc"/></r></xsl:template>
</xsl:stylesheet>
