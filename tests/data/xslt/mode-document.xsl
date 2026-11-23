<xsl:stylesheet version="3.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:m="urn:modes" exclude-result-prefixes="m">
<!-- deep-copy and shallow-copy of a document node into a sequence keep a
     document node; typed="yes" accepts a document node -->
<xsl:mode name="m:deep" on-no-match="deep-copy"/>
<xsl:mode name="m:shallow" on-no-match="shallow-copy"/>
<xsl:mode name="m:typed" typed="yes"/>
<xsl:template match="/">
  <xsl:variable name="d" as="node()*"><xsl:apply-templates select="/" mode="m:deep"/></xsl:variable>
  <xsl:variable name="s" as="node()*"><xsl:apply-templates select="/" mode="m:shallow"/></xsl:variable>
  <r deep="{count($d)} {$d instance of document-node()} {count($d/doc/*)}"
     shallow="{count($s)} {$s instance of document-node()} {count($s/doc/*)}">
    <xsl:apply-templates select="/" mode="m:typed"/>
  </r>
</xsl:template>
<xsl:template match="/" mode="m:typed"><typed/></xsl:template>
</xsl:stylesheet>
