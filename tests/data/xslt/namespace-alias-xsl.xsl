<?xml version="1.0" encoding="UTF-8"?>
<!-- The XSLT namespace as the result of an alias whose stylesheet
     namespace is not in scope at the literal result element: its binding
     is copied (Saxon), so the QName in the attribute keeps its prefix. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:namespace-alias xmlns:a="urn:a" stylesheet-prefix="a" result-prefix="xsl"/>
  <xsl:template match="/">
    <out type="xsl:T"/>
  </xsl:template>
</xsl:stylesheet>
