<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a global parameter with select and content (white space xml:space keeps): XTSE0620 -->
<xsl:param name="p" select="1" xml:space="preserve"> </xsl:param>
<xsl:template match="/"><r><xsl:value-of select="$p"/></r></xsl:template>
</xsl:stylesheet>
