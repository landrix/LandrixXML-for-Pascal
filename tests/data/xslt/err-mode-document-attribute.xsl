<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- shallow-copy of the document node: an attribute at its top -->
<xsl:mode name="m:s" on-no-match="shallow-copy"/>
<xsl:template match="doc" mode="m:s"><xsl:attribute name="a">1</xsl:attribute></xsl:template>
<xsl:template match="/"><out><xsl:apply-templates select="/" mode="m:s"/></out></xsl:template>
</xsl:stylesheet>
