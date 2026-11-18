<?xml version="1.0" encoding="UTF-8"?>
<!-- let (XPath 3.0, as Saxon runs it in a 2.0 stylesheet): a binding is
     evaluated when it is first used, so $a does not need $b, and $b may
     refer to $a; bindings see the earlier ones and the let's focus; a
     variable of a let is no number in a pattern predicate -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:f="urn:f"
  exclude-result-prefixes="f">
  <xsl:output method="text"/>
  <xsl:variable name="a" select="let $unused := $b return 1"/>
  <xsl:variable name="b" select="$a + 1"/>
  <xsl:function name="f:sum">
    <xsl:param name="n"/>
    <xsl:sequence select="if ($n = 0) then 0 else let $r := f:sum($n - 1) return $r + $n"/>
  </xsl:function>
  <xsl:template match="/">
    <xsl:value-of select="$a, $b"/>
    <xsl:text>|</xsl:text>
    <xsl:value-of select="for $i in 1 to 3 return let $j := $i * $i, $k := $j + 1 return $k"/>
    <xsl:text>|</xsl:text>
    <xsl:value-of select="(10, 20, 30)[let $p := position() return $p mod 2 = 1]"/>
    <xsl:text>|</xsl:text>
    <xsl:value-of select="let $e := error() return 'unused'"/>
    <xsl:text>|</xsl:text>
    <xsl:value-of select="let $n := patterns/name() return $n"/>
    <xsl:text>|</xsl:text>
    <xsl:value-of select="let $s := (for $i in 1 to 3 return $i * 2), $t := 5 return ($t, $s)"/>
    <xsl:text>|</xsl:text>
    <xsl:value-of select="f:sum(100)"/>
    <xsl:text>|</xsl:text>
    <xsl:apply-templates select="patterns/b" mode="m"/>
    <xsl:text>|</xsl:text>
    <xsl:apply-templates select="patterns/b" mode="n"/>
  </xsl:template>
  <xsl:template match="*[if (self::a) then error() else true()][let $a := true(), $v := $a return $v]" mode="n">
    <xsl:text>matched</xsl:text>
  </xsl:template>
  <xsl:template match="*[if (self::a) then error() else true()][let $v := true() return $v]" mode="m">
    <xsl:text>matched</xsl:text>
  </xsl:template>
</xsl:stylesheet>
