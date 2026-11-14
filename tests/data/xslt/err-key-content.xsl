<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- xsl:key with use and content -->
<xsl:key name="k" match="*" use="@id"><xsl:text>x</xsl:text></xsl:key>
<xsl:template match="/"/>
</xsl:stylesheet>
