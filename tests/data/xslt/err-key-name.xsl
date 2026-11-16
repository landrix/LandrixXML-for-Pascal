<?xml version="1.0" encoding="UTF-8"?>
<!-- XTSE0020: the name of xsl:key is not a QName. -->
<xsl:stylesheet version="2.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:key name="a::b" match="*" use="1"/>
  <xsl:template match="/">
    <out/>
  </xsl:template>
</xsl:stylesheet>
