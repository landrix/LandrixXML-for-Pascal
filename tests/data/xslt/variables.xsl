<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xs="http://www.w3.org/2001/XMLSchema">
  <xsl:param name="p" select="'default'"/>
  <xsl:variable name="g" select="concat('g-', $p)"/>
  <xsl:variable name="tree"><t><u>1</u><u>2</u></t></xsl:variable>
  <xsl:variable name="seq" as="xs:integer*" select="(1, 2, 3)"/>
  <xsl:variable name="later" select="$after * 2"/>
  <xsl:variable name="after" select="21"/>
  <xsl:template match="/">
    <out>
      <g><xsl:value-of select="$g"/></g>
      <t><xsl:value-of select="count($tree//u)"/>,<xsl:value-of select="$tree"/></t>
      <s><xsl:value-of select="$seq" separator="+"/>=<xsl:value-of select="sum($seq)"/></s>
      <l><xsl:value-of select="$later"/></l>
      <xsl:variable name="g" select="'local'"/>
      <shadow><xsl:value-of select="$g"/></shadow>
      <xsl:for-each select="1 to 3">
        <xsl:variable name="i" select=". * 10"/>
        <i><xsl:value-of select="$i"/></i>
      </xsl:for-each>
      <xsl:variable name="els" as="element()*"><e n="1"/><e n="2"/></xsl:variable>
      <els><xsl:value-of select="count($els), $els/@n, count($els/..)"/></els>
      <xsl:call-template name="named"><xsl:with-param name="x" select="5"/></xsl:call-template>
      <xsl:call-template name="named"/>
    </out>
  </xsl:template>
  <xsl:template name="named">
    <xsl:param name="x" select="1"/>
    <xsl:param name="y" as="xs:integer" select="$x + 1"/>
    <n x="{$x}" y="{$y}" g="{$g}"/>
  </xsl:template>
</xsl:stylesheet>
