<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- bytes that are no UTF-8 with the encoding given: FOUT1190 (Saxon) -->
<xsl:template match="/"><o><xsl:value-of select="unparsed-text('_text-bad.txt', 'UTF-8')"/></o></xsl:template>
</xsl:stylesheet>
