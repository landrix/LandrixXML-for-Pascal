<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- current() in a stylesheet function: XTDE1360 -->
<xsl:function name="f:f"><xsl:sequence select="name(current())"/></xsl:function>
<xsl:template match="/"><r><xsl:value-of select="f:f()"/></r></xsl:template>
</xsl:stylesheet>
