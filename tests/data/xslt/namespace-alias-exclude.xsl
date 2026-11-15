<?xml version="1.0" encoding="UTF-8"?>
<!-- xsl:namespace-alias with exclude-result-prefixes: an excluded aliased
     namespace still gives the result binding, so does an excluded
     result namespace of an alias (XSLT 2.0, Saxon); an alias to no
     namespace leaves the default namespace of the stylesheet alone. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns="urn:d" xmlns:a="urn:a" xmlns:r="urn:r" xmlns:n="urn:n" xmlns:t="urn:t" exclude-result-prefixes="a r t">
  <xsl:namespace-alias stylesheet-prefix="a" result-prefix="r"/>
  <xsl:namespace-alias xmlns="" stylesheet-prefix="n" result-prefix="#default"/>
  <xsl:namespace-alias xmlns:b="urn:b" stylesheet-prefix="b" result-prefix="t"/>
  <xsl:template match="/">
    <out type="r:T"/>
  </xsl:template>
</xsl:stylesheet>
