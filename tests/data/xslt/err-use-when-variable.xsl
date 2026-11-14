<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:variable name="g" select="1"/>
<xsl:template match="/" use-when="$g = 1"><r/></xsl:template>
</xsl:stylesheet>
