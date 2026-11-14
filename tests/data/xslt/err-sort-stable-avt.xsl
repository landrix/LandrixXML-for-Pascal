<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- a computed stable attribute is checked when the sort runs -->
<xsl:template match="/"><r><xsl:for-each select="(1,2)"><xsl:sort stable="{'maybe'}"/><xsl:value-of select="."/></xsl:for-each></r></xsl:template>
</xsl:stylesheet>
