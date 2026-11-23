<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a variable with select and content: XTSE0620 -->
<xsl:template match="/"><r><xsl:variable name="v" select="1">two</xsl:variable><xsl:value-of select="$v"/></r></xsl:template>
</xsl:stylesheet>
