<?xml version="1.0" encoding="UTF-8"?>
<!-- XTSE0010: xsl:character-map contains xsl:output-character only. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:character-map name="a">
    <xsl:attribute name="x"/>
  </xsl:character-map>
  <xsl:template match="/">
    <out>a</out>
  </xsl:template>
</xsl:stylesheet>
