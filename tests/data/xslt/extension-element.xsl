<?xml version="1.0" encoding="UTF-8"?>
<!-- extension-element-prefixes: an element in an extension namespace runs
     its xsl:fallback children in order (other children are ignored); one
     that is not evaluated raises nothing; the extension namespaces are
     no namespace nodes of literal result elements; the attribute also
     works on xsl:template and (in the XSLT namespace) on literal result
     elements, as does exclude-result-prefixes on xsl:template -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:ext="urn:ext" xmlns:e="urn:e" xmlns:x="urn:x" xmlns:o="urn:o" extension-element-prefixes="ext">
  <ext:data>a top-level element in an extension namespace is ignored</ext:data>
  <xsl:template match="/" extension-element-prefixes="e" exclude-result-prefixes="o">
    <out available="{element-available('ext:foo')}">
      <ext:foo x="1">text<xsl:fallback>F1</xsl:fallback><b/><xsl:fallback>F2<ext:bar><xsl:fallback>nested</xsl:fallback></ext:bar></xsl:fallback></ext:foo>
      <xsl:if test="false()"><ext:never/></xsl:if>
      <e:a><xsl:fallback><xsl:variable name="v" select="'variable'"/><xsl:value-of select="$v"/></xsl:fallback></e:a>
      <lit xsl:extension-element-prefixes="x"><x:y><xsl:fallback>fx</xsl:fallback></x:y></lit>
      <xsl:variable name="t"><ext:foo><xsl:fallback>in a variable</xsl:fallback></ext:foo></xsl:variable>
      <xsl:copy-of select="$t"/>
    </out>
  </xsl:template>
</xsl:stylesheet>
