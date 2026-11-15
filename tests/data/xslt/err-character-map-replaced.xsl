<?xml version="1.0" encoding="UTF-8"?>
<!-- XTSE1590: a map replaced by one of higher precedence still names an
     undeclared map. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:import href="_err-character-map-replaced.xsl"/>
  <xsl:output use-character-maps="m"/>
  <xsl:character-map name="m">
    <xsl:output-character character="a" string="b"/>
  </xsl:character-map>
  <xsl:template match="/">
    <out>a</out>
  </xsl:template>
</xsl:stylesheet>
