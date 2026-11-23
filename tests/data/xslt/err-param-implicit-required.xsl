<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a parameter without default whose type needs a value, not supplied: XTDE0700 -->
<xsl:template match="/"><r><xsl:apply-templates select="doc"/></r></xsl:template>
<xsl:template match="doc"><xsl:param name="p" as="xs:integer"/><xsl:value-of select="$p"/></xsl:template>
</xsl:stylesheet>
