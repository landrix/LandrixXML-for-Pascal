<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- what select allows besides: xsl:fallback in xsl:sequence, comments, empty xsl:value-of -->
<xsl:template match="/"><r><xsl:sequence select="1"><xsl:fallback/></xsl:sequence><xsl:value-of select="2"><!-- c --></xsl:value-of><xsl:value-of/><xsl:variable name="v" select="3">
  </xsl:variable><xsl:value-of select="$v"/></r></xsl:template>
</xsl:stylesheet>
