<?xml version="1.0" encoding="UTF-8"?>
<!-- XTSE1580: two character maps of one name and import precedence. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:character-map name="a"/>
  <xsl:character-map name="a"/>
  <xsl:template match="/">
    <out>a</out>
  </xsl:template>
</xsl:stylesheet>
