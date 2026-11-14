<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- collation with group-starting-with -->
<xsl:template match="/"><o><xsl:for-each-group select="/*" group-starting-with="*"
  collation="http://www.w3.org/2005/xpath-functions/collation/codepoint"/></o></xsl:template>
</xsl:stylesheet>
