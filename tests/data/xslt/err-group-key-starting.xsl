<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- current-grouping-key() with group-starting-with -->
<xsl:template match="/"><o><xsl:for-each-group select="/*" group-starting-with="*"><xsl:value-of
  select="current-grouping-key()"/></xsl:for-each-group></o></xsl:template>
</xsl:stylesheet>
