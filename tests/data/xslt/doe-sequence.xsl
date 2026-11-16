<?xml version="1.0" encoding="UTF-8"?>
<!-- raw text a function or a template with as returns stays raw when
     it is added to the result (xsl:sequence, xsl:call-template), not
     when it is copied (xsl:copy-of, also into an element a function
     builds); in a message only its string counts -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:f="urn:f" exclude-result-prefixes="f">
  <xsl:function name="f:raw">
    <xsl:text disable-output-escaping="yes">&lt;c&gt;</xsl:text>
  </xsl:function>
  <xsl:function name="f:typed" as="item()*">
    <xsl:value-of select="'&lt;d&gt;'" disable-output-escaping="yes"/>
  </xsl:function>
  <xsl:function name="f:copied" as="element()">
    <x><xsl:copy-of select="f:raw()"/></x>
  </xsl:function>
  <xsl:template name="t" as="text()">
    <xsl:text disable-output-escaping="yes">&lt;b&gt;</xsl:text>
  </xsl:template>
  <xsl:template match="/">
    <xsl:variable name="v" select="f:raw()"/>
    <xsl:message><xsl:sequence select="f:raw()"/></xsl:message>
    <out>
      <a><xsl:call-template name="t"/>|<xsl:sequence select="f:raw()"/>|<xsl:sequence select="f:typed()"/></a>
      <b><xsl:copy-of select="f:raw()"/>|<xsl:sequence select="$v"/>|<xsl:copy-of select="$v"/>|<xsl:sequence select="f:copied()"/></b>
    </out>
  </xsl:template>
</xsl:stylesheet>
