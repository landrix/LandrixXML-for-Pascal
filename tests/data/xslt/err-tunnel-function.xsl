<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:f="urn:f">
<!-- XTSE0020: a parameter of a function is no tunnel parameter -->
<xsl:function name="f:f"><xsl:param name="p" tunnel="yes"/></xsl:function>
<xsl:template match="/"><r/></xsl:template>
</xsl:stylesheet>
