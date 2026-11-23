<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- use-accumulators: the first name decides the error -->
<xsl:mode use-accumulators="missing q:two"/>
<xsl:template match="/"><r><xsl:apply-templates select="doc"/></r></xsl:template>
</xsl:stylesheet>
