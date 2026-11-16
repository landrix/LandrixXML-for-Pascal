<?xml version="1.0" encoding="UTF-8"?>
<!-- doctype-system and doctype-public, method xml: the declaration before
     the first element (after a comment), the system literal in single
     quotes when it has a double quote; a public identifier alone or an
     empty system identifier writes none -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output doctype-system='s"q.dtd' doctype-public="-//P'Q//EN"/>
  <xsl:template match="/">
    <xsl:comment>before</xsl:comment>
    <p:root xmlns:p="urn:p"><a>t</a></p:root>
    <xsl:comment>after</xsl:comment>
  </xsl:template>
</xsl:stylesheet>
