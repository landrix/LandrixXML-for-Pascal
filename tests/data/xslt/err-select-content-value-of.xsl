<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- xsl:value-of with select and content (xsl:fallback is content): XTSE0870 -->
<xsl:template match="/"><r><xsl:value-of select="1"><xsl:fallback/></xsl:value-of></r></xsl:template>
</xsl:stylesheet>
