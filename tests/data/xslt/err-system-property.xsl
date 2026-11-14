<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- XTDE1390: no QName or an unbound prefix -->
<xsl:template match="/"><o><xsl:value-of select="system-property('q:version')"/></o></xsl:template>
</xsl:stylesheet>
