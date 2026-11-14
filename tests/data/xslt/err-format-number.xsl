<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- a picture with two decimal separators -->
<xsl:template match="/"><o><xsl:value-of select="format-number(1, '0.0.0')"/></o></xsl:template>
</xsl:stylesheet>
