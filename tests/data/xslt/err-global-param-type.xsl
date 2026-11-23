<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- the default of a global parameter does not match its type: XTTE0590 -->
<xsl:param name="p" as="xs:integer" select="'a'"/>
<xsl:template match="/"><r><xsl:value-of select="$p"/></r></xsl:template>
</xsl:stylesheet>
