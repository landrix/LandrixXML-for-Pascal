<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- a character that is no XML character: FOUT1190 also without an
     encoding (bytes not in UTF-8 are FOUT1200) -->
<xsl:template match="/"><o><xsl:value-of select="unparsed-text('_text-nul.txt')"/></o></xsl:template>
</xsl:stylesheet>
