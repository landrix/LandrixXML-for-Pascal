<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- two values for one property at the same precedence -->
<xsl:decimal-format name="a" minus-sign="~"/>
<xsl:decimal-format name="a" minus-sign="!"/>
<xsl:template match="/"/>
</xsl:stylesheet>
