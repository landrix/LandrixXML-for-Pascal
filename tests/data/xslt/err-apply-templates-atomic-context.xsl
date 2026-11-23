<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- xsl:apply-templates without select on an atomic context item: XTTE0510 -->
<xsl:template match="/"><r><xsl:for-each select="1 to 2"><xsl:apply-templates/></xsl:for-each></r></xsl:template>
</xsl:stylesheet>
