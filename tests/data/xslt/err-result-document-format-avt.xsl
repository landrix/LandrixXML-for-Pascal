<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- XTDE1460: a computed format no xsl:output names -->
<xsl:output name="yes" method="text"/>
<xsl:template match="/"><xsl:result-document format="{'n', 'o'}"><r/></xsl:result-document></xsl:template>
</xsl:stylesheet>
