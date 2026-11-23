<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- on-multiple-match="fail" for xsl:next-match -->
<xsl:mode on-multiple-match="fail"/>
<xsl:template match="a" priority="2"><A/><xsl:next-match/></xsl:template>
<xsl:template match="a" priority="1"><B/></xsl:template><xsl:template match="*:a" priority="1"><C/></xsl:template>
<xsl:template match="doc"><xsl:apply-templates select="a"/></xsl:template>
<xsl:template match="/"><r><xsl:apply-templates select="doc"/></r></xsl:template>
</xsl:stylesheet>
