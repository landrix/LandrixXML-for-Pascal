<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- a global parameter without default whose type needs a value: XTDE0700 -->
<xsl:param name="p" as="xs:integer"/>
<xsl:template match="/"><r><xsl:value-of select="$p"/></r></xsl:template>
</xsl:stylesheet>
