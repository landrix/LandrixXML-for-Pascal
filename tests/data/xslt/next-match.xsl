<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- xsl:next-match and xsl:apply-imports: priorities, union patterns,
     parameters, named templates, modes, the built-in rule and the
     precedences of imported modules -->
<xsl:import href="_next-match-imported.xsl"/>
<xsl:output method="xml" indent="no" omit-xml-declaration="yes"/>
<xsl:template match="/"><r><xsl:apply-templates select="doc/*"/><m><xsl:apply-templates select="doc/a" mode="m"/></m></r></xsl:template>
<xsl:template match="a" priority="3"><p3><xsl:next-match><xsl:with-param name="p" select="'from3'"/></xsl:next-match></p3></xsl:template>
<xsl:template match="a" priority="2"><xsl:param name="p" select="'none'"/><p2 p="{$p}"><xsl:call-template name="named"/></p2></xsl:template>
<xsl:template name="named"><xsl:variable name="v"><xsl:next-match/></xsl:variable><named><xsl:copy-of select="$v"/></named></xsl:template>
<xsl:template match="a | node()"><u n="{name()}"><xsl:next-match/></u></xsl:template>
<xsl:template match="b | *" priority="5"><e><xsl:next-match/></e></xsl:template>
<xsl:template match="b" priority="4"><b4><xsl:apply-imports/></b4></xsl:template>
<xsl:template match="c"><c0><xsl:next-match/></c0></xsl:template>
<xsl:template match="a" mode="m"><mm><xsl:next-match/></mm></xsl:template>
<xsl:template match="*" mode="m" priority="-1"><mlow><xsl:apply-imports/></mlow></xsl:template>
</xsl:stylesheet>
