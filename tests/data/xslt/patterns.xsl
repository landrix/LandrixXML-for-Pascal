<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- document-node() with an argument; white space in patterns does not
     change the default priority -->
<xsl:template match="document-node(element(x))">miss</xsl:template>
<xsl:template match="document-node( element(patterns) )">[doc]<xsl:apply-templates/></xsl:template>
<xsl:template match="element (a)">[wrong]</xsl:template>
<xsl:template match="a">[a]</xsl:template>
<xsl:template match="child :: b">[wrong]</xsl:template>
<xsl:template match="b">[b]</xsl:template>
</xsl:stylesheet>
