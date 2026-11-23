<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- xsl:sequence with select and content other than xsl:fallback: XTSE3185 -->
<xsl:template match="/"><r><xsl:sequence select="1">two</xsl:sequence></r></xsl:template>
</xsl:stylesheet>
