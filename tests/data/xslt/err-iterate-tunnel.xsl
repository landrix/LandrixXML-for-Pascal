<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- a tunnel xsl:with-param in xsl:next-iteration -->
<xsl:template match="/">
<r><xsl:iterate select="1 to 3"><xsl:param name="p" select="0"/><xsl:next-iteration><xsl:with-param name="p" select="1" tunnel="yes"/></xsl:next-iteration></xsl:iterate></r>
</xsl:template>
</xsl:stylesheet>
