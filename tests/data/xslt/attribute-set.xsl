<?xml version="1.0" encoding="UTF-8"?>
<!-- Attribute sets: merged declarations (import precedence, then
     declaration order), nested use-attribute-sets, literal attributes
     replacing those of a set, xsl:element and xsl:copy, the focus and the
     current template rule of the using instruction, global and local
     variables, prefixed names, a set used before it is declared. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:p="urn:p" exclude-result-prefixes="p">
  <xsl:import href="_attribute-set-imported.xsl"/>
  <xsl:output indent="no"/>

  <xsl:variable name="g" select="'global'"/>

  <xsl:template match="/">
    <out>
      <xsl:apply-templates select="doc/item"/>
      <copied>
        <xsl:for-each select="doc/item[1]">
          <xsl:copy use-attribute-sets="base"/>
        </xsl:for-each>
        <xsl:for-each select="doc/item[1]/text()">
          <xsl:copy use-attribute-sets="base"/>
        </xsl:for-each>
      </copied>
      <xsl:element name="computed" use-attribute-sets="p:named later"/>
      <empty xsl:use-attribute-sets=""/>
      <order xsl:use-attribute-sets="later base"/>
    </out>
  </xsl:template>

  <xsl:template match="item" priority="2">
    <entry xsl:use-attribute-sets="base outer" literal="mine" a="literal">
      <xsl:value-of select="."/>
    </entry>
  </xsl:template>

  <xsl:template match="item" priority="1">
    <xsl:value-of select="concat('next-', @id)"/>
  </xsl:template>

  <!-- merged with the imported base (lower precedence: first) -->
  <xsl:attribute-set name="base">
    <xsl:attribute name="a" select="'main'"/>
    <xsl:attribute name="pos" select="position()"/>
  </xsl:attribute-set>

  <xsl:attribute-set name="base">
    <xsl:attribute name="c">second declaration</xsl:attribute>
  </xsl:attribute-set>

  <xsl:attribute-set name="outer" use-attribute-sets="inner p:named">
    <xsl:attribute name="outer">
      <xsl:variable name="v" select="name()"/>
      <xsl:value-of select="$v, $g"/>
    </xsl:attribute>
    <xsl:attribute name="rule">
      <xsl:next-match/>
    </xsl:attribute>
  </xsl:attribute-set>

  <xsl:attribute-set name="inner">
    <xsl:attribute name="inner" select="@id"/>
    <xsl:attribute name="literal">from the set</xsl:attribute>
  </xsl:attribute-set>

  <xsl:attribute-set name="p:named">
    <xsl:attribute name="named">p</xsl:attribute>
  </xsl:attribute-set>

  <xsl:attribute-set name="later">
    <xsl:attribute name="a">later</xsl:attribute>
  </xsl:attribute-set>
</xsl:stylesheet>
