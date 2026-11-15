<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:f="urn:f"
  exclude-result-prefixes="f">
<!-- tunnel parameters: passed on through templates that do not declare
     them (apply-templates, call-template, next-match, apply-imports, the
     built-in rules, for-each), replaced by a new tunnel xsl:with-param,
     apart from the parameters that are not tunnel parameters, and not
     passed into stylesheet functions -->
<xsl:import href="_tunnel-imported.xsl"/>
<xsl:output omit-xml-declaration="yes"/>
<xsl:template match="/">
  <r><xsl:apply-templates select="doc">
    <xsl:with-param name="t" tunnel="yes" select="'one'"/>
  </xsl:apply-templates></r>
</xsl:template>
<xsl:template match="doc">
  <xsl:param name="t" select="'none'"/>
  <doc plain="{$t}"><xsl:apply-templates/></doc>
</xsl:template>
<xsl:template match="a">
  <xsl:param name="t" tunnel="yes"/>
  <a t="{$t}"><xsl:for-each select="b"><xsl:call-template name="named"/></xsl:for-each>
    <xsl:apply-templates select="c"><xsl:with-param name="t" tunnel="yes" select="'two'"/></xsl:apply-templates>
    <f><xsl:value-of select="f:f()"/></f></a>
</xsl:template>
<xsl:template name="named">
  <xsl:param name="t" tunnel="yes" as="xs:string" xmlns:xs="http://www.w3.org/2001/XMLSchema"/>
  <named t="{$t}"/>
</xsl:template>
<xsl:template match="c" priority="2">
  <xsl:param name="t" tunnel="yes"/>
  <c t="{$t}"><xsl:next-match/></c>
</xsl:template>
<xsl:template match="c">
  <xsl:param name="t" tunnel="yes"/>
  <c2 t="{$t}"><xsl:apply-imports><xsl:with-param name="u" tunnel="yes" select="'three'"/></xsl:apply-imports></c2>
</xsl:template>
<xsl:function name="f:f"><xsl:call-template name="in-function"/></xsl:function>
<xsl:template name="in-function"><xsl:param name="t" tunnel="yes" select="'not passed'"/><xsl:value-of select="$t"/></xsl:template>
</xsl:stylesheet>
