<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- a zero digit that is no zero -->
<xsl:decimal-format name="z" zero-digit="1"/>
<xsl:template match="/"/>
</xsl:stylesheet>
