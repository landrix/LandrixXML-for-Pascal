<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- xsl:next-match: without a priority attribute every branch of a union
     pattern is a rule of its own and may choose the template again -->
<xsl:template match="/"><r><xsl:apply-templates select="doc"/>|<xsl:apply-templates select="doc" mode="b"/></r></xsl:template>
<xsl:template match="doc[true()] | doc[1]">X<xsl:next-match/></xsl:template>
<xsl:template match="doc | node()" mode="b">Y<xsl:next-match/></xsl:template>
</xsl:stylesheet>
