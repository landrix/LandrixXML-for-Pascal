<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- required on a parameter of a function -->
<xsl:function name="f:id"><xsl:param name="p" required="no"/><xsl:sequence select="$p"/></xsl:function>
<xsl:template match="/"/>
</xsl:stylesheet>
