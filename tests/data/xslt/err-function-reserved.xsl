<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- a function in a reserved namespace -->
<xsl:function name="xml:foo"><xsl:sequence select="1"/></xsl:function>
<xsl:template match="/"/>
</xsl:stylesheet>
