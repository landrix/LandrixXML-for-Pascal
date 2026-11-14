<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- xsl:for-each-group: group-by (several keys, numbers, NaN), group-adjacent,
     group-starting-with, group-ending-with; current-group() in templates;
     position() and last() of the groups -->
<xsl:template match="/">
  <r>
    <by><xsl:for-each-group select="doc/i" group-by="tokenize(@k, ' ')">
      <g key="{current-grouping-key()}" p="{position()}/{last()}" n="{count(current-group())}" first="{.}"/>
    </xsl:for-each-group></by>
    <num><xsl:for-each-group select="doc/i" group-by="number(@n)">
      <g key="{current-grouping-key()}" n="{count(current-group())}"/>
    </xsl:for-each-group></num>
    <mixed><xsl:for-each-group select="(1, '1', 1.0, xs:untypedAtomic('1'), true(), 'true')" group-by=".">
      <g n="{count(current-group())}"/>
    </xsl:for-each-group></mixed>
    <adj><xsl:for-each-group select="doc/*" group-adjacent="name()">
      <g key="{current-grouping-key()}" n="{count(current-group())}"><xsl:apply-templates select="."/></g>
    </xsl:for-each-group></adj>
    <start><xsl:for-each-group select="doc/*" group-starting-with="h">
      <g n="{count(current-group())}" first="{name()}"/>
    </xsl:for-each-group></start>
    <end><xsl:for-each-group select="doc/*" group-ending-with="h">
      <g n="{count(current-group())}" last="{name(current-group()[last()])}"/>
    </xsl:for-each-group></end>
    <empty><xsl:for-each-group select="()" group-by="."><g/></xsl:for-each-group></empty>
  </r>
</xsl:template>
<xsl:template match="*"><t c="{count(current-group())}"/></xsl:template>
</xsl:stylesheet>
