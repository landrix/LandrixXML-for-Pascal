<?xml version="1.0" encoding="UTF-8"?>
<!-- Two imported aliases of one precedence for one namespace are no
     error when an alias of higher precedence replaces them (XSLT 2.0;
     Saxon accepts this only when the higher alias has the result of one
     of them, as here). -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:a="urn:a" xmlns:r="urn:r">
  <xsl:import href="_namespace-alias-conflict.xsl"/>
  <xsl:namespace-alias stylesheet-prefix="a" result-prefix="r"/>
  <xsl:template match="/">
    <a:out/>
  </xsl:template>
</xsl:stylesheet>
