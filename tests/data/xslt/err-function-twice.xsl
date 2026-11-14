<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- two functions with the same name, arity and precedence -->
<xsl:function name="f:f"><xsl:sequence select="1"/></xsl:function>
<xsl:function name="f:f"><xsl:sequence select="2"/></xsl:function>
<xsl:template match="/"/>
</xsl:stylesheet>
