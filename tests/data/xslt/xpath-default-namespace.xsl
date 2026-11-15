<?xml version="1.0" encoding="UTF-8"?>
<!-- xpath-default-namespace: on xsl:stylesheet for expressions and
     patterns, overridden on an XSLT element and by
     xsl:xpath-default-namespace on a literal result element, "" for no
     namespace; attribute names are not affected; the names of
     xsl:strip-space are; type names in "as" with the XML Schema
     namespace as the default; the value without surrounding white space;
     on xsl:number, xsl:decimal-format and xsl:output too. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xpath-default-namespace=" urn:d ">
  <xsl:strip-space elements="list"/>
  <xsl:output xpath-default-namespace="urn:x"/>
  <xsl:decimal-format name="f" xpath-default-namespace="urn:x" expand-text="no" pattern-separator=";"/>
  <xsl:template match="/">
    <out>
      <xsl:apply-templates select="doc/item"/>
      <count><xsl:value-of select="count(//item[@n])"/></count>
      <none xsl:xpath-default-namespace=""><xsl:value-of select="count(//item)"/></none>
      <list><xsl:value-of select="count(doc/list/node())"/></list>
      <xsl:call-template name="typed"/>
    </out>
  </xsl:template>
  <xsl:template match="item">
    <i n="{@n}"><xsl:number count="item" xpath-default-namespace="urn:d"/>:<xsl:value-of select="."/></i>
  </xsl:template>
  <xsl:template name="typed" xpath-default-namespace="http://www.w3.org/2001/XMLSchema">
    <xsl:variable name="v" as="integer" select="xs:integer(3)" xmlns:xs="http://www.w3.org/2001/XMLSchema"/>
    <typed><xsl:value-of select="$v instance of integer, '7' cast as integer"/></typed>
  </xsl:template>
</xsl:stylesheet>
