<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- xsl:break with select and content -->
<xsl:template match="/">
<r><xsl:iterate select="1 to 3"><xsl:break select="1">x</xsl:break></xsl:iterate></r>
</xsl:template>
</xsl:stylesheet>
