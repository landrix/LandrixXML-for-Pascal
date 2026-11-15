<?xml version="1.0" encoding="UTF-8"?>
<!-- Base URIs of temporary trees as Saxon gives them: a with-param body
     (its own xml:base), a variable with as, a copied document (the
     original's), xsl:copy at the top of a sequence (the original's) and
     xsl:copy-of there (its xml:base against the instruction's base). -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xml:base="http://example.org/outer/">
  <xsl:template match="/">
    <out>
      <xsl:apply-templates select="*" mode="p" xml:base="http://ap/"><xsl:with-param name="q" xml:base="http://wp/"><w/></xsl:with-param></xsl:apply-templates>
      <xsl:variable name="w" xml:base="http://x.org/q/" as="element()"><z/></xsl:variable>
      <typed><xsl:value-of select="base-uri($w)"/></typed>
      <xsl:variable name="d" as="document-node()"><xsl:for-each select="/"><xsl:copy xml:base="http://copier/"><x/></xsl:copy></xsl:for-each></xsl:variable>
      <doc><xsl:value-of select="base-uri($d) = base-uri(/)"/></doc>
      <xsl:variable name="c" as="element()*" xml:base="http://v/"><xsl:for-each select="*"><xsl:copy/></xsl:for-each><xsl:copy-of select="*"/></xsl:variable>
      <copies><xsl:value-of select="for $e in $c return base-uri($e)"/></copies>
    </out>
  </xsl:template>
  <xsl:template match="*" mode="p"><xsl:param name="q"/><p><xsl:value-of select="base-uri($q), base-uri($q/w)"/></p></xsl:template>
</xsl:stylesheet>
