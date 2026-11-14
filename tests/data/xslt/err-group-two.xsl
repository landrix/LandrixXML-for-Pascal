<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- group-by and group-adjacent together -->
<xsl:template match="/"><o><xsl:for-each-group select="1" group-by="." group-adjacent="."/></o></xsl:template>
</xsl:stylesheet>
