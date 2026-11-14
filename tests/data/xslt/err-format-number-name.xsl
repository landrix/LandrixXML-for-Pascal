<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- a decimal format that is not declared -->
<xsl:template match="/"><o><xsl:value-of select="format-number(1, '0', 'none')"/></o></xsl:template>
</xsl:stylesheet>
