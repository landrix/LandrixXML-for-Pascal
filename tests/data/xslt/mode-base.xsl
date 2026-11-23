<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- deep-copy: a copied xml:base against the base URI of the original -->
<xsl:mode name="m:d" on-no-match="deep-copy"/>
<xsl:template match="/">
  <xsl:variable name="v" as="element()"><xsl:apply-templates select="doc/c" mode="m:d"/></xsl:variable>
  <r b="{base-uri($v)}"/>
</xsl:template>
</xsl:stylesheet>
