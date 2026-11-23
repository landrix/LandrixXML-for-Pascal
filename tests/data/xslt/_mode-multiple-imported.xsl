<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- imported by err-mode-apply-imports-multiple.xsl: two rules of one
     priority -->
<xsl:template match="a" priority="1"><B/></xsl:template><xsl:template match="*:a" priority="1"><C/></xsl:template>
</xsl:stylesheet>
