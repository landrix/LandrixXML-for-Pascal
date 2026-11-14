<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- white space in the stylesheet: comments go before white space is stripped; white space before xsl:param and xsl:sort goes even with xml:space -->
<xsl:template match="/">
<r>
<e>   h<!--c-->   </e>
<e>   <!--c-->h   </e>
<e>   <!--c-->   <?pi x?>   </e>
<xsl:call-template name="t"><xsl:with-param name="p" select="'v'"/></xsl:call-template>
</r>
</xsl:template>
<xsl:template name="t" xml:space="preserve">
  <xsl:param name="p"/>[<xsl:value-of select="$p"/>]</xsl:template>
</xsl:stylesheet>
