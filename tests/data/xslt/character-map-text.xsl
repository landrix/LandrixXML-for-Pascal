<?xml version="1.0" encoding="UTF-8"?>
<!-- Character maps with the text method. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="text" use-character-maps="m"/>
  <xsl:character-map name="m">
    <xsl:output-character character="&amp;" string="&amp;amp;"/>
    <xsl:output-character character="&#10;" string="[LF]&#10;"/>
  </xsl:character-map>
  <xsl:template match="/">
    <xsl:text>a &amp; b
c &lt; d
</xsl:text>
  </xsl:template>
</xsl:stylesheet>
