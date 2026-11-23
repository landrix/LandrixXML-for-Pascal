<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- xsl:with-param whose value does not match its own as: XTTE0590 -->
<xsl:template match="/"><r><xsl:call-template name="t"><xsl:with-param name="p" as="xs:integer" select="'a'"/></xsl:call-template></r></xsl:template>
<xsl:template name="t"><xsl:param name="p"/><xsl:value-of select="$p"/></xsl:template>
</xsl:stylesheet>
