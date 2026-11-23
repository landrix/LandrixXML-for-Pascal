<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a global variable (evaluated on first use) whose value does not match: XTTE0570 -->
<xsl:variable name="g" as="xs:integer" select="'a'"/>
<xsl:template match="/"><r><xsl:value-of select="$g"/></r></xsl:template>
</xsl:stylesheet>
