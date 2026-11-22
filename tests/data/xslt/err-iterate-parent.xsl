<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- xsl:break in a literal result element -->
<xsl:template match="/">
<r><xsl:iterate select="1 to 3"><b><xsl:break/></b></xsl:iterate></r>
</xsl:template>
</xsl:stylesheet>
