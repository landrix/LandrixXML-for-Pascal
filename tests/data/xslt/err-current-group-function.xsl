<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- current-group() in a function called in a group -->
<xsl:function name="f:c"><xsl:sequence select="count(current-group())"/></xsl:function>
<xsl:template match="/"><o><xsl:for-each-group select="1" group-by="."><g f="{f:c()}"/></xsl:for-each-group></o></xsl:template>
</xsl:stylesheet>
