<?xml version="1.0" encoding="UTF-8"?>
<!-- SERE0008: a mapped string with a character the encoding does not have. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output encoding="US-ASCII" use-character-maps="m"/>
  <xsl:character-map name="m">
    <xsl:output-character character="e" string="&#x20ac;"/>
  </xsl:character-map>
  <xsl:template match="/">
    <out>e</out>
  </xsl:template>
</xsl:stylesheet>
