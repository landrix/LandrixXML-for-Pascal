<?xml version="1.0" encoding="UTF-8"?>
<!-- cdata-section-elements: QNames (default namespace for unprefixed
     names), the union of every xsl:output, "]]>" split, characters the
     encoding lacks as references between sections, no character map in
     CDATA, white space in a CDATA element kept when indenting -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:p="urn:p" xmlns="urn:d" exclude-result-prefixes="#default">
  <xsl:output cdata-section-elements="p:a  b" encoding="US-ASCII" indent="yes" use-character-maps="m"/>
  <xsl:output cdata-section-elements="Q{}c"/>
  <xsl:character-map name="m">
    <xsl:output-character character="x" string="XX"/>
  </xsl:character-map>
  <xsl:template match="/">
    <out xmlns="">
      <p:a>x]]&gt;y&#xaa;&#xab;z&#13;]]]]&gt;&gt;</p:a>
      <p:a>&#xaa;</p:a>
      <p:a/>
      <b xmlns="urn:d">in default</b>
      <b>no namespace: x</b>
      <c><xsl:text>  </xsl:text><i/><xsl:text> </xsl:text><i/>t<i/></c>
      <c>line&#10;  break</c>
      <d>x</d>
    </out>
  </xsl:template>
</xsl:stylesheet>
