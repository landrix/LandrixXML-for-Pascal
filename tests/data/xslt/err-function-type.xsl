<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- an argument that does not have the parameter's type -->
<xsl:function name="f:f"><xsl:param name="n" as="xs:integer"/><xsl:sequence select="$n"/></xsl:function>
<xsl:template match="/"><r><xsl:value-of select="f:f(xs:date('2026-01-01'))"/></r></xsl:template>
</xsl:stylesheet>
