<?xml version="1.0" encoding="UTF-8"?>
<!-- XTSE0020: xsl:output-character with more than one character. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:character-map name="a">
    <xsl:output-character character="ab" string="x"/>
  </xsl:character-map>
  <xsl:template match="/">
    <out>a</out>
  </xsl:template>
</xsl:stylesheet>
