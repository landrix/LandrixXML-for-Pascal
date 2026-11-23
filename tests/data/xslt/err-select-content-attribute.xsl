<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- xsl:attribute with select and content: XTSE0840 -->
<xsl:template match="/"><r><xsl:attribute name="a" select="1">two</xsl:attribute></r></xsl:template>
</xsl:stylesheet>
