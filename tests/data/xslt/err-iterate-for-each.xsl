<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- xsl:break inside xsl:for-each in xsl:iterate -->
<xsl:template match="/">
<r><xsl:iterate select="1 to 3"><xsl:for-each select="."><xsl:if test=". = 2"><xsl:break/></xsl:if></xsl:for-each></xsl:iterate></r>
</xsl:template>
</xsl:stylesheet>
