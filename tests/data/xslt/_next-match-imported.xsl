<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- imported by next-match.xsl: lower precedence -->
<xsl:import href="_next-match-imported2.xsl"/>
<xsl:template match="a"><ia><xsl:next-match/></ia></xsl:template>
<xsl:template match="b"><ib><xsl:apply-imports/></ib></xsl:template>
<xsl:template match="*" mode="m"><im/></xsl:template>
</xsl:stylesheet>
