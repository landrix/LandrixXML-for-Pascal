<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/">
    <xsl:variable name="atts" as="attribute()*"><xsl:copy-of select="/r/@*"/><xsl:attribute name="z" select="'made'"/></xsl:variable>
    <xsl:variable name="doc" as="document-node()"><xsl:for-each select="/"><xsl:copy><k/></xsl:copy></xsl:for-each></xsl:variable>
    <out><xsl:attribute name="s" select="(1, 2)" separator=","/><xsl:copy-of select="$atts"/><c n="{count($atts)}" d="{count($doc/k)}"/></out>
  </xsl:template>
</xsl:stylesheet>
