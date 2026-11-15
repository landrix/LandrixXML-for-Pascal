<?xml version="1.0" encoding="UTF-8"?>
<!-- Base URIs at the top of a typed sequence as Saxon gives them:
     xsl:copy-of of an element or document keeps the source document URI,
     an element made by xsl:element, a literal result element in an
     xsl:function or a template with "as" has the static base of its
     instruction. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:f="urn:f" xml:base="http://s/a/">
  <xsl:function name="f:mk" as="element()" xml:base="http://s/fn/"><z/></xsl:function>
  <xsl:template name="t" as="element()" xml:base="http://s/tp/"><y/></xsl:template>
  <xsl:template match="/">
    <out>
      <xsl:variable name="e" as="element()*"><xsl:copy-of select="/r"/></xsl:variable>
      <xsl:variable name="d" as="document-node()*"><xsl:copy-of select="/"/></xsl:variable>
      <xsl:variable name="v" as="element()" xml:base="http://variable/"><xsl:element name="z" xml:base="http://element/"/></xsl:variable>
      <xsl:variable name="tt" as="element()"><xsl:call-template name="t"/></xsl:variable>
      <a><xsl:value-of select="base-uri($e) = base-uri(/), base-uri($d) = base-uri(/)"/></a>
      <b><xsl:value-of select="base-uri($v), base-uri(f:mk()), base-uri($tt)"/></b>
    </out>
  </xsl:template>
</xsl:stylesheet>
