<?xml version="1.0" encoding="UTF-8"?>
<!-- normalization-form: text, attribute values and CDATA sections are
     normalized, names and comments are not; a character map is applied
     first and its strings are not normalized (the text around them is,
     piece by piece) -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output normalization-form="NFC" cdata-section-elements="c" use-character-maps="m"/>
  <xsl:character-map name="m">
    <xsl:output-character character="q" string="Á"/>
    <xsl:output-character character="́" string="Y"/>
  </xsl:character-map>
  <xsl:template match="/">
    <xsl:comment>Á</xsl:comment>
    <out a="É" b="Á"><eÁ/>Ö|Å|<xsl:value-of select="concat('e', '̂')"/>|q|Á<c>x́Ü</c></out>
  </xsl:template>
</xsl:stylesheet>
