<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a key that is not declared -->
<xsl:template match="/"><o><xsl:value-of select="key('nokey', 'x')"/></o></xsl:template>
</xsl:stylesheet>
