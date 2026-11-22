<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- xsl:with-param for no parameter of the xsl:iterate -->
<xsl:template match="/">
<r><xsl:iterate select="1 to 3"><xsl:param name="p" select="0"/><xsl:next-iteration><xsl:with-param name="q" select="1"/></xsl:next-iteration></xsl:iterate></r>
</xsl:template>
</xsl:stylesheet>
