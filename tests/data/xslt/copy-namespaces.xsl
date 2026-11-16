<?xml version="1.0" encoding="UTF-8"?>
<!-- copy-namespaces="no": a copy has only the namespaces its names (and
     those of its attributes and descendants) need; below the top an element
     has those of the place the copy goes to, except a default namespace
     below a copied element in no namespace (as Saxon) -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    xmlns:a="urn:a" xmlns:d="urn:d" exclude-result-prefixes="a d">
  <xsl:template match="/">
    <out>
      <yes><xsl:copy-of select="/d:doc/a:x" copy-namespaces=" yes "/></yes>
      <no><xsl:copy-of select="/d:doc/a:x" copy-namespaces="no"/></no>
      <false><xsl:copy-of select="//d:y" copy-namespaces="false"/></false>
      <shallow><xsl:for-each select="/d:doc/a:x"><xsl:copy copy-namespaces="0"><xsl:copy-of select="@*"/></xsl:copy></xsl:for-each></shallow>
      <shallow-yes><xsl:for-each select="//d:y"><xsl:copy/></xsl:for-each></shallow-yes>
      <dd xmlns="urn:q"><xsl:copy-of select="//*:z" copy-namespaces="no"/><xsl:for-each select="//*:z"><xsl:copy copy-namespaces="no"/></xsl:for-each><xsl:copy-of select="//*:z"/><xsl:copy-of select="/" copy-namespaces="no"/></dd>
      <qq xmlns="urn:q"><xsl:copy-of select="//plain" copy-namespaces="no"/></qq>
      <xsl:variable name="v"><xsl:copy-of select="//d:y" copy-namespaces="no"/></xsl:variable>
      <var><xsl:value-of select="string-join(in-scope-prefixes($v/*), ',')"/></var>
    </out>
  </xsl:template>
</xsl:stylesheet>
