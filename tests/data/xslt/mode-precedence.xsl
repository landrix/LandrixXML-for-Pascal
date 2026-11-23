<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- xsl:mode: an attribute from the declaration of the highest import
     precedence that has it; equal values are no conflict; on-multiple-match
     fail with two branches of one union pattern -->
<xsl:import href="_mode-imported.xsl"/>
<xsl:mode on-no-match="shallow-copy" typed="0"/>
<xsl:mode on-no-match="shallow-copy" typed="false" on-multiple-match="fail" warning-on-multiple-match="yes"/>
<xsl:template match="/"><r><xsl:apply-templates select="doc"/></r></xsl:template>
<xsl:template match="a[1] | doc/*[1]"><A/></xsl:template>
<xsl:template match="b" priority="1"><B/></xsl:template>
<xsl:template match="b"><X/></xsl:template>
</xsl:stylesheet>
