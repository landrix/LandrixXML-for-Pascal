<?xml version="1.0" encoding="UTF-8"?>
<!-- with the text method nothing is escaped anyway -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:variable name="v"><t>x<xsl:text disable-output-escaping="yes">&lt;b/&gt;</xsl:text>y</t></xsl:variable>
  <xsl:output method="text"/><xsl:template match="/">
    <out a="{'&lt;'}">
      <xsl:attribute name="b"><xsl:value-of select="'&lt;'" disable-output-escaping="yes"/></xsl:attribute>
      <one><xsl:copy-of select="$v"/></one>
      <two><xsl:value-of select="$v"/></two>
      <three>p<xsl:value-of select="'&lt;i&gt;&amp;'" disable-output-escaping="yes"/>q</three>
      <four><xsl:comment><xsl:value-of select="'&lt;c&gt;'" disable-output-escaping="yes"/></xsl:comment></four>
      <five><xsl:value-of select="'&#xE9;'" disable-output-escaping="yes"/></five>
    </out>
  </xsl:template>
</xsl:stylesheet>
