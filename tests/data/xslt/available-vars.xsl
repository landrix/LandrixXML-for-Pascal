<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:p="urn:variables" xmlns:v0="http://www.w3.org/2005/xpath-functions">
<!-- a prefix that looks like an internal key of the XPath context -->
<xsl:output method="text"/>
<xsl:variable name="p:x" select="1"/>
<xsl:template match="/">
  <xsl:value-of separator="|" select="function-available('v0:true'), $p:x"/>
</xsl:template>
</xsl:stylesheet>
