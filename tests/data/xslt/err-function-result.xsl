<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a result that does not have the function's type -->
<xsl:function name="f:f" as="xs:integer"><xsl:sequence select="'x'"/></xsl:function>
<xsl:template match="/"><r><xsl:value-of select="f:f()"/></r></xsl:template>
</xsl:stylesheet>
