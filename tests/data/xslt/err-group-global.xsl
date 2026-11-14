<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a global variable read first inside a group has no current group -->
<xsl:variable name="g" select="count(current-group())"/>
<xsl:template match="/"><o><xsl:for-each-group select="1" group-by="."><xsl:value-of select="$g"/></xsl:for-each-group></o></xsl:template>
</xsl:stylesheet>
