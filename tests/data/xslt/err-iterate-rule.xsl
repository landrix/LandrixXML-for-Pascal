<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- no current template rule in xsl:iterate -->
<xsl:template match="/">
<r><xsl:apply-templates select="*"/></r>
</xsl:template>
<xsl:template match="doc"><xsl:iterate select="."><xsl:next-match/></xsl:iterate></xsl:template>
</xsl:stylesheet>
