<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a variable whose value does not match its type: XTTE0570 -->
<xsl:template match="/"><r><xsl:variable name="v" as="xs:integer" select="'a'"/><xsl:value-of select="$v"/></r></xsl:template>
</xsl:stylesheet>
