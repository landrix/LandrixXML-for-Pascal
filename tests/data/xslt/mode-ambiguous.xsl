<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" xmlns:f="urn:f" xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="m f xs">
<!-- on-multiple-match="fail": rules of a lower priority are not tried (the
     pattern below would terminate the transformation) -->
<xsl:mode on-multiple-match="fail"/>
<xsl:function name="f:t" as="xs:boolean"><xsl:message terminate="yes">evaluated</xsl:message><xsl:sequence select="true()"/></xsl:function>
<xsl:template match="doc/a" priority="2"><A/></xsl:template>
<xsl:template match="a[f:t()]"><X/></xsl:template>
<xsl:template match="doc"><xsl:apply-templates select="a"/></xsl:template>
<xsl:template match="/"><r><xsl:apply-templates select="doc"/></r></xsl:template>
</xsl:stylesheet>
