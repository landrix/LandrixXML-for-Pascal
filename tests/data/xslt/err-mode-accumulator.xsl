<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- use-accumulators names no accumulator -->
<xsl:mode use-accumulators="acc"/>
<xsl:template match="/"><r><xsl:apply-templates select="doc"/></r></xsl:template>
</xsl:stylesheet>
