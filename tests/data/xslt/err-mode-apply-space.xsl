<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- the mode of xsl:apply-templates is one EQName -->
<xsl:template match="/"><r><xsl:apply-templates select="doc" mode="Q{ urn:modes }m"/></r></xsl:template>
</xsl:stylesheet>
