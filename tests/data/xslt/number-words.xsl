<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- English words and ordinals (Saxon HE numbers in English whatever
     the language), letter-value, ordinal values -->
<xsl:template match="/"><r>
<xsl:for-each select="0, 1, 12, 20, 21, 99, 100, 101, 115, 200, 1000, 1001, 1100, 1990, 2013, 100001, 1234567, 21000000, 2147483647">
<n><xsl:number value="." format="w"/>|<xsl:number value="." format="W"/>|<xsl:number value="." format="Ww"/>|<xsl:number
  value="." format="w" ordinal="yes"/>|<xsl:number value="." format="Ww" ordinal="-e"/>|<xsl:number value="." format="W"
  ordinal="no"/>|<xsl:number value="." ordinal="yes"/>|<xsl:number value="." format="001" ordinal="yes"
  grouping-separator="," grouping-size="2"/>|<xsl:number value="." format="a" ordinal="yes"/>|<xsl:number value="."
  format="i" ordinal="yes"/>|<xsl:number value="." format="1" ordinal=""/></n>
</xsl:for-each>
<xsl:for-each select="1, 18, 19, 26, 300">
<l><xsl:number value="." format="i" letter-value="alphabetic"/>|<xsl:number value="." format="I"
  letter-value="{'alphabetic'}"/>|<xsl:number value="." format="i" letter-value=" traditional "/>|<xsl:number value="." format="i" letter-value=" alphabetic "/>|<xsl:number value="."
  format="a" letter-value="traditional"/></l>
</xsl:for-each>
<xsl:for-each select="' en ', 'de', 'x', 'i-klingon', 'a-b-c', 'en-GB'">
<g><xsl:number value="21" format="Ww" lang="{.}"/></g>
</xsl:for-each>
<e><xsl:number value="2" lang=""/>|<xsl:number value="2" ordinal="{' '}"/></e>
<m><xsl:number value="(3, 22, 101)" format="1. w, Ww" ordinal="yes"/></m>
</r></xsl:template>
</xsl:stylesheet>
