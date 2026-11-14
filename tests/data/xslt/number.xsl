<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- xsl:number: levels, count and from, format tokens, value, grouping -->
<xsl:template match="/">
  <r>
    <xsl:for-each select="//c">
      <n s="{position()}">
        <xsl:attribute name="single"><xsl:number/></xsl:attribute>
        <xsl:attribute name="multiple"><xsl:number level="multiple" count="s|c" format="1.a"/></xsl:attribute>
        <xsl:attribute name="any"><xsl:number level="any" format="0001"/></xsl:attribute>
        <xsl:attribute name="anystar"><xsl:number level="any" count="*" format="(i)"/></xsl:attribute>
        <xsl:attribute name="from"><xsl:number level="any" from="s" format="A"/></xsl:attribute>
        <xsl:attribute name="sel"><xsl:number select=".." format="I"/></xsl:attribute>
      </n>
    </xsl:for-each>
    <v><xsl:number value="(1, 2.5, 27, 1234567)" format="[1] " grouping-separator="," grouping-size="3"/></v>
    <v><xsl:number value="3" format="a"/>|<xsl:number value="28" format="A"/>|<xsl:number value="1999" format="i"/></v>
    <v><xsl:number value="(1, 2, 3)" format="1-a"/></v>
    <v><xsl:number value="(1, 2, 3)"/></v>
    <v><xsl:number value="()" format="x1y"/></v>
  </r>
</xsl:template>
</xsl:stylesheet>
