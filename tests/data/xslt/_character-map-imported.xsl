<?xml version="1.0" encoding="UTF-8"?>
<!-- Imported by character-map.xsl: an xsl:output and character maps of
     lower import precedence. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output use-character-maps="low"/>
  <xsl:character-map name="low">
    <xsl:output-character character="a" string="LOW-A"/>
    <xsl:output-character character="x" string="LOW-X"/>
  </xsl:character-map>
  <xsl:character-map name="twice">
    <xsl:output-character character="t" string="IMPORTED-T1"/>
  </xsl:character-map>
  <xsl:character-map name="twice">
    <xsl:output-character character="t" string="IMPORTED-T2"/>
  </xsl:character-map>
  <xsl:character-map name="replaced">
    <xsl:output-character character="z" string="IMPORTED-Z"/>
  </xsl:character-map>
</xsl:stylesheet>
