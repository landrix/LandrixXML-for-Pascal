<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m" default-mode="m:start">
<!-- [xsl:]default-mode: the mode of templates and xsl:apply-templates
     without one, #default and #unnamed, the initial mode -->
<xsl:template match="/">
  <r>
    <start><xsl:apply-templates select="//a"/></start>
    <unnamed><xsl:apply-templates select="//a" mode="#unnamed"/></unnamed>
    <eqname><xsl:apply-templates select="//a" mode="Q{urn:modes}two"/></eqname>
    <lre xsl:default-mode="m:two"><xsl:apply-templates select="//a"/>|<xsl:apply-templates select="//a" mode="#default"/></lre>
    <own><xsl:apply-templates select="//a" default-mode="#unnamed"/></own>
    <nested><xsl:call-template name="nested"/></nested>
  </r>
</xsl:template>
<xsl:template match="a">start</xsl:template>
<xsl:template match="a" mode="#unnamed">unnamed</xsl:template>
<xsl:template match="a" mode="m:two">two</xsl:template>
<xsl:template match="a" default-mode="m:three">three</xsl:template>
<xsl:template name="nested" default-mode="#unnamed">
  <xsl:if test="true()" default-mode="m:three"><xsl:apply-templates select="//a"/></xsl:if>
  <xsl:apply-templates select="//a"/>
  <xsl:for-each select="//b"><xsl:apply-templates select="../a" mode="#default"/></xsl:for-each>
</xsl:template>
</xsl:stylesheet>
