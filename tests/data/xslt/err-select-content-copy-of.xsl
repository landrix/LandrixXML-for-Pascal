<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- xsl:copy-of must be empty, also of xsl:fallback: XTSE0260 -->
<xsl:template match="/"><r><xsl:copy-of select="1"><xsl:fallback/></xsl:copy-of></r></xsl:template>
</xsl:stylesheet>
