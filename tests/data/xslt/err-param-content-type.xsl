<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- a parameter whose default is content that does not match: XTTE0570, not XTTE0600 -->
<xsl:template match="/"><r><xsl:call-template name="t"/></r></xsl:template>
<xsl:template name="t"><xsl:param name="p" as="xs:integer"><a/></xsl:param><xsl:value-of select="$p"/></xsl:template>
</xsl:stylesheet>
