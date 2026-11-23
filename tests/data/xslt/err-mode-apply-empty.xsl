<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- an empty mode of xsl:apply-templates -->
<xsl:template match="/"><r><xsl:apply-templates select="doc" mode=" "/></r></xsl:template>
</xsl:stylesheet>
