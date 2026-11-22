<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- the value of xsl:next-iteration converted to the type of the parameter -->
<xsl:template match="/">
<r><xsl:iterate select="1 to 3"><xsl:param name="p" as="xs:integer" select="0"/><xsl:next-iteration><xsl:with-param name="p" select="string(.)"/></xsl:next-iteration></xsl:iterate></r>
</xsl:template>
</xsl:stylesheet>
