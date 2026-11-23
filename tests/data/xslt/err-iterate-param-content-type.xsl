<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="xs">
<!-- an xsl:iterate parameter whose content does not match: XTTE0570, not XTTE0600 -->
<xsl:template match="/"><r><xsl:iterate select="1 to 2"><xsl:param name="q" as="xs:integer">abc</xsl:param><xsl:value-of select="$q"/></xsl:iterate></r></xsl:template>
</xsl:stylesheet>
