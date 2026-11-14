<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a group-adjacent key of two values -->
<xsl:template match="/"><o><xsl:for-each-group select="1" group-adjacent="(1, 2)"/></o></xsl:template>
</xsl:stylesheet>
