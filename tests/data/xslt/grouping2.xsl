<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:f="urn:f" exclude-result-prefixes="xs f">
<!-- keys: QNames by expanded name, equal dateTimes, 0 and -0, the grouping
     key atomized; NaN in key() -->
<xsl:key name="nan" match="*" use="xs:double('NaN')"/>
<xsl:template match="/">
  <r>
    <q><xsl:for-each-group select="(QName('urn:a', 'x'), QName('urn:b', 'x'), QName('urn:a', 'p:x'))" group-by=".">
      <g n="{count(current-group())}"/></xsl:for-each-group></q>
    <d><xsl:for-each-group select="(xs:dateTime('2020-01-01T00:00:00Z'), xs:dateTime('2020-01-01T01:00:00+01:00'))"
      group-by="."><g n="{count(current-group())}"/></xsl:for-each-group></d>
    <z><xsl:for-each-group select="(0, -0e0, 0.0)" group-by="."><g n="{count(current-group())}"/></xsl:for-each-group></z>
    <k><xsl:for-each-group select="/*" group-by="@k"><g a="{current-grouping-key() instance of xs:anyAtomicType}"
      v="{current-grouping-key()}"/></xsl:for-each-group></k>
    <nan><xsl:value-of select="count(key('nan', xs:double('NaN')))"/></nan>
  </r>
</xsl:template>
</xsl:stylesheet>
