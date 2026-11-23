<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- the default priority of the pattern . is -1, of .[predicate] +1 (XSLT 3.0) -->
<xsl:template match="."><dot/></xsl:template>
<xsl:template match="/"><r><xsl:apply-templates select="doc/*"/></r></xsl:template>
<xsl:template match="a | b"><name/></xsl:template>
<xsl:template match=".[@k]"><predicate/></xsl:template>
</xsl:stylesheet>
