<?xml version="1.0" encoding="UTF-8"?>
<!-- xsl:key with a sequence constructor instead of use (a local variable,
     xsl:call-template, several values), merged with a declaration of the
     same name with use; a key name with a prefix, resolved by key() with
     the namespaces of the calling expression. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:p="urn:p" xmlns:q="urn:p" exclude-result-prefixes="p q">
  <xsl:key name="p:k" match="item">
    <xsl:variable name="n" select="string(@n)"/>
    <xsl:sequence select="$n, upper-case($n)"/>
    <xsl:call-template name="extra"/>
  </xsl:key>
  <xsl:key name="p:k" match="other" use="@n"/>
  <xsl:template name="extra">
    <xsl:sequence select="concat('x-', @n)"/>
  </xsl:template>
  <xsl:template match="/">
    <out>
      <a><xsl:value-of select="key('p:k', 'a')/name()"/></a>
      <b><xsl:value-of select="key('q:k', 'A')/@n"/></b>
      <c><xsl:value-of select="count(key('p:k', 'x-b'))"/></c>
      <d><xsl:value-of select="key('p:k', 'z')/name()"/></d>
    </out>
  </xsl:template>
</xsl:stylesheet>
