<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- the principal result of xsl:result-document as text; an empty
     implicit result besides it is no conflict -->
<xsl:template match="/"><xsl:apply-templates select="*"/><xsl:result-document method="text"><r>a<x>b</x></r></xsl:result-document></xsl:template>
<xsl:template match="doc"/>
</xsl:stylesheet>
