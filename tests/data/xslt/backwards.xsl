<?xml version="1.0" encoding="UTF-8"?>
<!-- Backwards compatible processing (version below 2.0), expected output
     from Saxon HE 12.9: the first item in xsl:value-of, attribute value
     templates, xsl:number and sort keys, XPath 1.0 compatibility mode in
     the expressions, key() with strings, a parameter the template does not
     declare, arguments of functions; mixed with XSLT 2.0 parts. -->
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:f="urn:f" xmlns:xs="http://www.w3.org/2001/XMLSchema" exclude-result-prefixes="f xs">
  <xsl:import href="_backwards-imported.xsl"/>
  <xsl:output method="xml" indent="no"/>
  <xsl:key name="id" match="x" use="@id"/>
  <xsl:key name="v" match="x" use="."/>
  <xsl:function name="f:d"><xsl:param name="p" as="xs:double"/><xsl:sequence select="$p"/></xsl:function>
  <xsl:function name="f:s"><xsl:param name="p" as="xs:string?"/><xsl:sequence select="concat('[', $p, ']')"/></xsl:function>
  <xsl:template match="/">
    <r a="{//x}" b="{//x/@id} {count(//x)}">
      <value-of><xsl:value-of select="//x"/>|<xsl:value-of select="//x" separator=","/>|<xsl:value-of select="1 to 3"/></value-of>
      <number><xsl:number value="//x"/>|<xsl:number value="()"/>|<xsl:number value="'abc'" format="(1)"/>|<xsl:number value="-3"/>|<xsl:number value="1 div 0"/>|<xsl:number value="2.5"/>|<xsl:number value="(3, 4)" format="a"/></number>
      <sort><xsl:for-each select="//x"><xsl:sort select="(@id, 'z')"/><xsl:value-of select="@id"/></xsl:for-each></sort>
      <xpath><xsl:value-of select="//x + 1"/>|<xsl:value-of select="'a' + 1"/>|<xsl:value-of select="//x = 1"/>|<xsl:value-of select="'10' &gt; '9'"/>|<xsl:value-of select="true() = 'false'"/>|<xsl:value-of select="substring('abcd', '2')"/>|<xsl:value-of select="string-length(//x)"/>|<xsl:value-of select="1 div 0"/>|<xsl:value-of select="floor('2.5')"/></xpath>
      <key><xsl:value-of select="count(key('v', 2))"/>|<xsl:value-of select="key('id', //x/@id)/@id"/>|<xsl:value-of select="count(key('k', 2.0))"/></key>
      <functions><xsl:value-of select="f:d('7') + 1"/>|<xsl:value-of select="f:s(5)"/>|<xsl:value-of select="f:s(//x)"/>|<xsl:value-of select="format-number('abc', '0')"/>|<xsl:value-of select="format-number(//x, '0.0')"/>|<xsl:value-of select="generate-id(//x) = generate-id(/d/x[1])"/>|<xsl:value-of select="system-property('xsl:supports-backwards-compatibility')"/></functions>
      <params><xsl:call-template name="t"><xsl:with-param name="undeclared" select="1"/><xsl:with-param name="p" select="//x"/></xsl:call-template></params>
      <mixed xsl:version="2.0"><xsl:value-of select="//x"/>|<xsl:value-of select="1 to 3"/></mixed>
      <xsl:call-template name="two"/>
    </r>
  </xsl:template>
  <xsl:template name="t">
    <xsl:param name="p"/>
    <xsl:value-of select="$p"/>|<xsl:value-of select="count($p)"/>
  </xsl:template>
</xsl:stylesheet>
