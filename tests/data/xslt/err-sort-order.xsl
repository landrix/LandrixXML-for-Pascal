<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xs="http://www.w3.org/2001/XMLSchema">
<xsl:template match="/"><r><xsl:for-each select="(1,2)"><xsl:sort order="up"/><xsl:value-of select="."/></xsl:for-each></r></xsl:template>
</xsl:stylesheet>
