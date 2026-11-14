<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- select that gives no node -->
<xsl:template match="/"><r><xsl:number select="1"/></r></xsl:template>
</xsl:stylesheet>
