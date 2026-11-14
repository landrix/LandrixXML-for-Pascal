<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<!-- the static base URI is the module's; document() resolves against
     the base URI of its node (xml:base) -->
<xsl:template match="/">
  <r s="{replace(string(static-base-uri()), '.*/', '')}" u="{replace(resolve-uri('x.xml'), '.*/', '')}"
    e="{count(resolve-uri(()))}"><xsl:value-of select="document(/base/@href)"/>
    <xsl:variable name="t"><x href="_data.xml"/></xsl:variable>
    <t v="{document($t/x/@href)/*/@v}"/></r>
</xsl:template>
</xsl:stylesheet>
