<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- a global variable with a type that needs a value and none: XTTE0570 -->
<xsl:variable name="v" as="xs:integer"/>
<xsl:template match="/"><r><xsl:value-of select="$v"/></r></xsl:template>
</xsl:stylesheet>
