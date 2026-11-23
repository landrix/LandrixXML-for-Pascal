<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- the result of a template does not match its type: XTTE0505 -->
<xsl:template match="/"><r><xsl:call-template name="t"/></r></xsl:template>
<xsl:template name="t" as="xs:integer"><xsl:sequence select="'a'"/></xsl:template>
</xsl:stylesheet>
