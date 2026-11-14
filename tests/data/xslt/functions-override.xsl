<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- two functions of the same precedence, replaced by one of a higher -->
<xsl:import href="_functions-twice.xsl"/>
<xsl:function name="f:v"><xsl:sequence select="3"/></xsl:function>
<xsl:template match="/"><r><xsl:value-of select="f:v()"/></r></xsl:template>
</xsl:stylesheet>
