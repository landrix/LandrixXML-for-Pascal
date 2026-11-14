<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- use-when: declarations, instructions and literal result elements left out when false; only the availability functions and no context -->
<xsl:include href="_does-not-exist.xsl" use-when="false()"/>
<xsl:template name="t" use-when="false()">wrong</xsl:template>
<xsl:template name="t" use-when="function-available('concat')">right</xsl:template>
<xsl:variable name="v" select="1" use-when="element-available('xsl:no-such-thing')"/>
<xsl:variable name="v" select="2" use-when="element-available('xsl:sort')"/>
<xsl:template match="/">
<r>
<a><xsl:call-template name="t"/></a>
<b><xsl:value-of select="$v"/></b>
<c><xsl:if test="true()" use-when="false()">no</xsl:if><xsl:if test="true()" use-when="true()">yes</xsl:if></c>
<d><x xsl:use-when="false()"/><y xsl:use-when="system-property('xsl:vendor') != ''">vendor</y></d>
<e><xsl:choose><xsl:when test="true()" use-when="false()">1</xsl:when><xsl:when test="false()">3</xsl:when><xsl:otherwise>2</xsl:otherwise></xsl:choose></e>
<f><xsl:value-of select="function-available('regex-group', 1), function-available('no-such-function'), element-available('xsl:if')" use-when="function-available('format-number', 2) and not(function-available('format-number', 7))"/></f>
<g><b xsl:use-when="ends-with(static-base-uri(), 'use-when.xsl')">base</b></g>
</r>
</xsl:template>
</xsl:stylesheet>
