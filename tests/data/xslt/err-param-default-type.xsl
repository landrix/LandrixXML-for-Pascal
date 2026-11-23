<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- the default of a template parameter does not match: XTTE0600 -->
<xsl:template match="/"><r><xsl:call-template name="t"/></r></xsl:template>
<xsl:template name="t"><xsl:param name="p" as="xs:integer" select="1.5"/><xsl:value-of select="$p"/></xsl:template>
</xsl:stylesheet>
