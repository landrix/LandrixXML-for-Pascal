<?xml version="1.0" encoding="UTF-8"?>
<!-- XTSE1600: a character map that uses itself indirectly. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:character-map name="a" use-character-maps="b"/>
  <xsl:character-map name="b" use-character-maps="a"/>
  <xsl:template match="/">
    <out>a</out>
  </xsl:template>
</xsl:stylesheet>
