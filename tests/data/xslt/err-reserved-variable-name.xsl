<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a local variable in a reserved namespace: XTSE0080 -->
<xsl:template match="/"><r><xsl:variable name="xs:v" select="1"/><xsl:value-of select="$xs:v"/></r></xsl:template>
</xsl:stylesheet>
