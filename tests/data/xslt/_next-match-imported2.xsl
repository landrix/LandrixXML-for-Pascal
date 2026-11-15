<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- imported by _next-match-imported.xsl: the lowest precedence -->
<xsl:template match="*"><low n="{name()}"><xsl:apply-templates/></low></xsl:template>
<xsl:template match="b" priority="9"><ib2><xsl:next-match/></ib2></xsl:template>
</xsl:stylesheet>
