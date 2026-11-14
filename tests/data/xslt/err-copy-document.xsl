<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- an attribute in a document node made by xsl:copy -->
<xsl:template match="/"><out><xsl:copy><xsl:attribute name="a">v</xsl:attribute></xsl:copy></out></xsl:template>
</xsl:stylesheet>
