<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- stylesheet functions: typed parameters and result, recursion,
     constructed nodes, calls from patterns and globals, the one with the
     higher import precedence -->
<xsl:import href="_functions-imported.xsl"/>
<xsl:variable name="g" select="f:fact(5)"/>
<xsl:function name="f:fact" as="xs:integer">
  <xsl:param name="n" as="xs:integer"/>
  <xsl:sequence select="if ($n le 1) then 1 else $n * f:fact($n - 1)"/>
</xsl:function>
<xsl:function name="f:label">
  <xsl:param name="e" as="element()"/>
  <xsl:param name="p" as="xs:string"/>
  <xsl:choose>
    <xsl:when test="$e/@k"><xsl:value-of select="concat($p, $e/@k)"/></xsl:when>
    <xsl:otherwise><xsl:value-of select="concat($p, local-name($e))"/></xsl:otherwise>
  </xsl:choose>
</xsl:function>
<xsl:function name="f:wrap" as="element()">
  <xsl:param name="s"/>
  <w><xsl:value-of select="$s"/></w>
</xsl:function>
<xsl:function name="f:untyped">
  <xsl:param name="v" as="xs:double"/>
  <xsl:sequence select="$v * 2"/>
</xsl:function>
<xsl:template match="item[f:label(., '') = 'two']">[pattern]</xsl:template>
<xsl:template match="/">
  <r g="{$g}" o="{f:over()}" u="{f:untyped(/functions/item[1]/@n)}">
    <xsl:for-each select="functions/item"><l><xsl:value-of select="f:label(., '-')"/></l></xsl:for-each>
    <xsl:copy-of select="f:wrap('x'), f:wrap(1)/.."/>
    <c><xsl:value-of select="count(f:wrap('y')/..)"/></c>
    <xsl:apply-templates select="functions/item"/>
  </r>
</xsl:template>
<xsl:function name="f:over"><xsl:sequence select="'main'"/></xsl:function>
</xsl:stylesheet>
