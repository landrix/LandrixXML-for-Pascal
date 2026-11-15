<?xml version="1.0" encoding="UTF-8"?>
<!-- xsl:namespace-alias with stylesheet-prefix="#default" and no default
     namespace: the elements in no namespace get the result namespace. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" xmlns:r="urn:r">
  <xsl:namespace-alias stylesheet-prefix="#default" result-prefix="r"/>
  <xsl:template match="/">
    <out a="1"><in/></out>
  </xsl:template>
</xsl:stylesheet>
