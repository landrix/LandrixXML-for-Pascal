<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:q="urn:q" xmlns:z="urn:z"
  exclude-result-prefixes="z">
  <xsl:template match="/">
    <out xmlns="urn:default" a="{1 + 1}" b="{{lit}}">
      <xsl:element name="q:made" namespace="urn:other"><xsl:attribute name="q:att" select="'v'"/></xsl:element>
      <xsl:element name="plain"/>
      <xsl:element name="{concat('dyn', 1)}"><xsl:attribute name="x">a<xsl:value-of select="2"/>b</xsl:attribute></xsl:element>
      <none xmlns=""><inner/></none>
      <xsl:comment> note </xsl:comment>
      <xsl:processing-instruction name="target" select="'data'"/>
      <xsl:copy-of select="/doc"/>
      <xsl:for-each select="/doc/item"><xsl:copy><xsl:attribute name="copied">yes</xsl:attribute><xsl:value-of select="."/></xsl:copy></xsl:for-each>
      <xsl:sequence select="(1, 'two', 3.5)"/>
      <xsl:text>&lt;&amp;&gt;"</xsl:text>
      <att v="&lt;&quot;&#10;&#9;&amp;"/>
      <dup a="1"><xsl:attribute name="a">2</xsl:attribute></dup>
      <xsl:document><d/></xsl:document>
    </out>
  </xsl:template>
</xsl:stylesheet>
