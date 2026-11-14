<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:xs="http://www.w3.org/2001/XMLSchema">
<!-- xsl:sort in xsl:apply-templates (between with-param), xsl:for-each-group and xsl:perform-sort -->
<xsl:template match="/">
<r>
<xsl:apply-templates select="//i">
  <xsl:with-param name="p" select="'-'"/>
  <xsl:sort select="@n" data-type="number" order="descending"/>
</xsl:apply-templates>
<groups>
<xsl:for-each-group select="//i" group-by="@g">
  <xsl:sort select="count(current-group())"/>
  <xsl:sort select="current-grouping-key()" order="descending"/>
  <g key="{current-grouping-key()}" pos="{position()}" size="{count(current-group())}"/>
</xsl:for-each-group>
</groups>
<sorted><xsl:perform-sort select="//i/@n"><xsl:sort select="number(.)"/></xsl:perform-sort></sorted>
<sorted2><xsl:value-of>
  <xsl:perform-sort><xsl:sort select="." order="descending"/><xsl:sequence select="('x','z','y')"/></xsl:perform-sort>
</xsl:value-of></sorted2>
</r>
</xsl:template>
<xsl:template match="i"><xsl:param name="p"/><v n="{@n}" p="{$p}" pos="{position()}"/></xsl:template>
</xsl:stylesheet>
