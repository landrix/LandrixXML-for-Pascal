<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- xsl:next-iteration outside xsl:iterate -->
<xsl:template match="/">
<r><xsl:call-template name="t"/></r>
</xsl:template>
<xsl:template name="t"><xsl:if test="true()"><xsl:next-iteration/></xsl:if></xsl:template>
</xsl:stylesheet>
