<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- XTDE1440: no QName or an unbound prefix -->
<xsl:template match="/"><o><xsl:value-of select="element-available('q:x')"/></o></xsl:template>
</xsl:stylesheet>
