<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- xsl:with-param in a reserved namespace: XTSE0080 -->
<xsl:template match="/"><r><xsl:call-template name="t"><xsl:with-param name="xs:p" select="1"/></xsl:call-template></r></xsl:template>
<xsl:template name="t"/>
</xsl:stylesheet>
