<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a key used in its own use expression -->
<xsl:key name="k" match="*" use="key('k', 'x')"/>
<xsl:template match="/"><o><xsl:value-of select="count(key('k', 'x'))"/></o></xsl:template>
</xsl:stylesheet>
