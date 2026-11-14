<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xs="http://www.w3.org/2001/XMLSchema">
<!-- sort keys of types without an order between them -->
<xsl:template match="/"><r><xsl:for-each select="(1,'a')"><xsl:sort select="."/><xsl:value-of select="."/></xsl:for-each></r></xsl:template>
</xsl:stylesheet>
