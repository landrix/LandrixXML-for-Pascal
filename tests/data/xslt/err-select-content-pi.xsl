<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- xsl:processing-instruction with select and content: XTSE0880 -->
<xsl:template match="/"><r><xsl:processing-instruction name="p" select="1">two</xsl:processing-instruction></r></xsl:template>
</xsl:stylesheet>
