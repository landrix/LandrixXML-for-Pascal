<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- no focus in xsl:on-completion -->
<xsl:template match="/">
<r><xsl:iterate select="1 to 3"><xsl:on-completion><xsl:value-of select="position()"/></xsl:on-completion><xsl:value-of select="."/></xsl:iterate></r>
</xsl:template>
</xsl:stylesheet>
