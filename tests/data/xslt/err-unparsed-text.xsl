<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- a text resource that is not there -->
<xsl:template match="/"><o><xsl:value-of select="unparsed-text('_none.txt')"/></o></xsl:template>
</xsl:stylesheet>
