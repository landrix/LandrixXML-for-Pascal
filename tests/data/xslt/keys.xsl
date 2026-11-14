<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- xsl:key and key(): several values, in another document and a
     subtree, keys declared twice, numeric use values -->
<xsl:key name="t" match="e" use="tokenize(@t, ' ')"/>
<xsl:key name="id" match="e" use="@id"/>
<xsl:key name="id" match="x" use="@ref"/>
<xsl:key name="num" match="n" use="xs:integer(@v)"/>
<xsl:key name="data" match="item" use="@code"/>
<xsl:template match="/">
  <r>
    <a><xsl:value-of select="key('t', 'a')/@id"/></a>
    <b><xsl:value-of select="key('t', ('b', 'a'))/@id"/></b>
    <id><xsl:value-of select="for $n in key('id', '2') return name($n)"/></id>
    <sub><xsl:value-of select="key('t', 'a', /doc/sub)/@id"/></sub>
    <num><xsl:value-of select="count(key('num', 1))"/>|<xsl:value-of select="count(key('num', '1'))"/></num>
    <none><xsl:value-of select="count(key('t', 'zz'))"/></none>
    <doc><xsl:value-of select="key('data', 'B', doc('_data2.xml'))"/></doc>
    <in><xsl:for-each select="doc/x"><xsl:value-of select="key('id', @ref)/@t"/></xsl:for-each></in>
  </r>
</xsl:template>
</xsl:stylesheet>
