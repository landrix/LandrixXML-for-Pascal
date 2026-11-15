<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:f="urn:f">
<!-- XTDE0560: no current template rule in a stylesheet function -->
<xsl:function name="f:f"><xsl:next-match/></xsl:function>
<xsl:template match="/"><r><xsl:sequence select="f:f()"/></r></xsl:template>
</xsl:stylesheet>
