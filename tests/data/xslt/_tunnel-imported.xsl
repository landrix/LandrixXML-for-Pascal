<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- imported by tunnel.xsl -->
<xsl:template match="c">
  <xsl:param name="t" tunnel="yes"/>
  <xsl:param name="u" tunnel="yes"/>
  <ic t="{$t}" u="{$u}"/>
</xsl:template>
</xsl:stylesheet>
