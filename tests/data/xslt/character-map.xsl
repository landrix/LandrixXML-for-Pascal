<?xml version="1.0" encoding="UTF-8"?>
<!-- Character maps with the xml method: the maps of every xsl:output
     (import precedence, then declaration order, the later mapping wins),
     use-character-maps in a map (its own characters win), a map of higher
     precedence replacing an imported one, mapped strings written as they
     are, attribute values, no mapping in comments, processing instructions,
     names and namespace URIs, a non-ASCII character, white space with a
     mapped character (text, not indentation), two imported maps of one
     name replaced by one of higher precedence, standard attributes on
     xsl:output-character, attributes wrapped by their mapped length (two more for each
     mapped character, as Saxon counts). -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:p="urn:p">
  <xsl:import href="_character-map-imported.xsl"/>
  <xsl:output use-character-maps="m1 replaced"/>
  <xsl:output use-character-maps="p:m2 twice" indent="yes"/>
  <xsl:character-map name="twice">
    <xsl:output-character character="t" string="MAIN-T" version="2.0"/>
  </xsl:character-map>
  <xsl:character-map name="m1">
    <xsl:output-character character="a" string="M1-A"/>
    <xsl:output-character character="b" string="M1-B"/>
    <xsl:output-character character="&lt;" string="&lt;"/>
    <xsl:output-character character="j" string="JJJJJJJJJJJJJJJJJJJJJJJJJJJJJ"/>
    <xsl:output-character character="w" string="WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW"/>
  </xsl:character-map>
  <xsl:character-map name="p:m2" use-character-maps="nested">
    <xsl:output-character character="b" string="M2-B"/>
    <xsl:output-character character="c" string="M2-C"/>
  </xsl:character-map>
  <xsl:character-map name="nested">
    <xsl:output-character character="c" string="NESTED-C"/>
    <xsl:output-character character="d" string="&amp;d;"/>
    <xsl:output-character character="&#xe9;" string="&#x20ac;"/>
    <xsl:output-character character=" " string="_"/>
  </xsl:character-map>
  <xsl:character-map name="replaced">
    <xsl:output-character character="y" string="MAIN-Y"/>
  </xsl:character-map>
  <xsl:template match="/">
    <out xmlns:q="urn:abc">
      <text>a b c d x y z &lt; &#xe9; &amp;</text>
      <attr v="a b&lt;c&quot;d"/>
      <xsl:comment>a b c d</xsl:comment>
      <xsl:processing-instruction name="pi">a b c d</xsl:processing-instruction>
      <bad/>
      <space><xsl:text> </xsl:text><e/></space>
      <t>t</t>
      <wrap v="w" k="k"/>
      <edge v="jj" k="k"/>
    </out>
  </xsl:template>
</xsl:stylesheet>
