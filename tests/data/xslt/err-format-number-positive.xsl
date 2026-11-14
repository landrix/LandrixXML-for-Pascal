<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a bad positive sub-picture, a negative value -->
<xsl:template match="/"><o><xsl:value-of select="format-number(-1, 'abc;0')"/></o></xsl:template>
</xsl:stylesheet>
