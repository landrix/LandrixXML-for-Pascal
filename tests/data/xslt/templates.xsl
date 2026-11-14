<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:p="urn:p">
  <xsl:template match="/">
    <out><xsl:apply-templates/><m><xsl:apply-templates select="//a" mode="m"/></m></out>
  </xsl:template>
  <xsl:template match="a">[a <xsl:value-of select="@x"/>:<xsl:apply-templates/>]</xsl:template>
  <xsl:template match="b/a" priority="2">[b/a <xsl:value-of select="."/>]</xsl:template>
  <xsl:template match="*">{<xsl:value-of select="name()"/>:<xsl:apply-templates select="@*|node()"/>}</xsl:template>
  <xsl:template match="p:*">(p <xsl:value-of select="local-name()"/>)</xsl:template>
  <xsl:template match="@*">@<xsl:value-of select="name()"/>=<xsl:value-of select="."/>;</xsl:template>
  <xsl:template match="text()[. = 'tail']">TAIL</xsl:template>
  <xsl:template match="a" mode="m"><i><xsl:value-of select="position()"/>/<xsl:value-of select="last()"/></i></xsl:template>
</xsl:stylesheet>
