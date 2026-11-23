<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- xsl:with-param with select and content: XTSE0620 -->
<xsl:template match="/"><r><xsl:call-template name="t"><xsl:with-param name="p" select="1">two</xsl:with-param></xsl:call-template></r></xsl:template>
<xsl:template name="t"><xsl:param name="p"/><xsl:value-of select="$p"/></xsl:template>
</xsl:stylesheet>
