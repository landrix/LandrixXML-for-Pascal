<?xml version="1.0" encoding="UTF-8"?>
<!-- xsl:namespace-alias on literal result elements (also in an imported
     module) and their attributes, the namespace nodes (an alias binding
     replaces another binding of the result prefix), #default on both
     sides, an alias to no namespace, not xsl:element or xsl:attribute,
     the higher import precedence; and the classic use, writing a
     stylesheet. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:a="urn:alias" xmlns:r="urn:result" xmlns:n="urn:null" xmlns:axsl="urn:axsl"
  exclude-result-prefixes="n">
  <xsl:import href="_namespace-alias-imported.xsl"/>
  <xsl:namespace-alias stylesheet-prefix="a" result-prefix="r"/>
  <xsl:namespace-alias stylesheet-prefix="n" result-prefix="#default"/>
  <xsl:namespace-alias stylesheet-prefix="axsl" result-prefix="xsl"/>
  <xsl:template match="/">
    <out>
      <a:e a:x="1" y="{1 + 1}"><a:f/></a:e>
      <e xmlns:r="urn:other"><a:g/></e>
      <n:h n:z="1"/>
      <xsl:element name="a:i"/>
      <j><xsl:attribute name="a:k">1</xsl:attribute></j>
      <xsl:call-template name="imported"/>
      <axsl:stylesheet version="2.0">
        <axsl:template match="/"><axsl:value-of select="1"/></axsl:template>
      </axsl:stylesheet>
    </out>
  </xsl:template>
</xsl:stylesheet>
